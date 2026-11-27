import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/rule.dart';
import '../services/xpath_service.dart';
import '../services/storage_service.dart';
import '../widgets/danmaku_overlay.dart';
import '../widgets/danmaku_heatmap.dart';
import 'detail_page.dart';

class SubtitleItem {
  final Duration start;
  final Duration end;
  final String text;
  SubtitleItem(this.start, this.end, this.text);
}

class PlayerPage extends StatefulWidget {
  final AnimeRule rule;
  final String episodeUrl;
  final String title;
  final String animeTitle;

  const PlayerPage({
    super.key,
    required this.rule,
    required this.episodeUrl,
    required this.title,
    required this.animeTitle,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _xpath = XPathService();
  final _storage = StorageService();
  final GlobalKey _globalKey = GlobalKey();

  VideoPlayerController? _controller;
  bool _loading = true;
  String? _resolvedUrl;
  String? _error;
  
  // ====== 网页媒体流监听与接管 ======
  Set<String> _sniffedUrls = {}; 
  bool _isWebViewMode = false; 
  String? _webViewCookies; 

  double _playbackSpeed = 1.0;
  Timer? _sleepTimer;
  Timer? _progressTimer;
  int _sleepMinutesRemaining = 0;

  // 弹幕与 OP/ED 配置
  List<DanmakuItem> _danmakus = [];
  final _danmakuController = TextEditingController();
  bool _showDanmakuInput = false;
  bool _danmakuEnabled = true;
  List<String> _blockWords = [];
  double _danmakuOpacity = 1.0;
  Duration? _opEndTime;
  bool _showSkipOpBtn = false;

  // 字幕配置
  List<SubtitleItem> _subtitles = [];
  String? _currentSubtitleText;
  bool _subtitleEnabled = true;

  // 手势控制状态
  String? _gestureTip;
  Timer? _gestureTipTimer;
  double _dragStartX = 0;
  double _dragStartY = 0;
  Duration _dragStartPosition = Duration.zero;
  double _startBrightness = 0.5;
  double _startVolume = 0.5;
  bool _isDragging = false;

  String get _danmakuKey => 'danmaku_${base64Url.encode(utf8.encode(widget.episodeUrl))}';
  String get _opKey => 'op_end_${base64Url.encode(utf8.encode(widget.episodeUrl))}';
  String get _progressKey => 'progress_${base64Url.encode(utf8.encode(widget.episodeUrl))}';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    VolumeController.instance.showSystemUI = false;
    final prefs = await SharedPreferences.getInstance();
    _playbackSpeed = prefs.getDouble('playback_speed') ?? 1.0;
    _danmakuEnabled = prefs.getBool('danmaku_enabled') ?? true;
    _blockWords = prefs.getStringList('danmaku_block_words') ?? [];
    _danmakuOpacity = prefs.getDouble('danmaku_opacity') ?? 1.0;
    final opMs = prefs.getInt(_opKey);
    if (opMs != null) _opEndTime = Duration(milliseconds: opMs);

    await _resolve();
  }

  void _showTip(String text) {
    _gestureTipTimer?.cancel();
    setState(() => _gestureTip = text);
    _gestureTipTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _gestureTip = null);
    });
  }

  Future<void> _resolve() async {
    try {
      final url = await _xpath.resolveEpisodeLink(widget.rule, widget.episodeUrl);
      if (!mounted) return;
      _resolvedUrl = url;

      await _storage.addHistory(HistoryItem(
        ruleId: widget.rule.id,
        ruleName: widget.rule.name,
        animeTitle: widget.animeTitle,
        episodeTitle: widget.title,
        episodeUrl: widget.episodeUrl,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await _loadDanmakus();

      if (_isDirectVideo(url)) {
        await _initPlayer(url);
      } else {
        setState(() {
          _isWebViewMode = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _resolvedUrl = null;
          _loading = false;
        });
      }
    }
  }

  Future<void> _initPlayer(String url) async {
    setState(() {
      _loading = true;
      _isWebViewMode = false;
    });

    try {
      final headers = {
        'Referer': _resolvedUrl ?? widget.episodeUrl,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      };
      if (_webViewCookies != null && _webViewCookies!.isNotEmpty) {
        headers['Cookie'] = _webViewCookies!;
      }

      final c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: headers,
      );
      await c.initialize();
      
      if (!mounted) {
        await c.dispose();
        return;
      }
      
      setState(() {
        _controller = c;
        _loading = false;
      });
      c.setPlaybackSpeed(_playbackSpeed);
      
      final prefs = await SharedPreferences.getInstance();
      final savedMs = prefs.getInt(_progressKey) ?? 0;
      if (savedMs > 5000 && savedMs < c.value.duration.inMilliseconds - 10000) {
        await c.seekTo(Duration(milliseconds: savedMs));
        _showTip('已为您续播至 ${_formatDuration(Duration(milliseconds: savedMs))}');
      }
      
      c.play();
      
      c.addListener(() {
        if (!mounted) return;
        if (_subtitleEnabled && _subtitles.isNotEmpty) {
          final current = c.value.position;
          final sub = _subtitles.firstWhere(
            (s) => current >= s.start && current <= s.end,
            orElse: () => SubtitleItem(Duration.zero, Duration.zero, ''),
          );
          if (_currentSubtitleText != sub.text) {
            setState(() => _currentSubtitleText = sub.text);
          }
        }

        if (_danmakuEnabled) setState(() {});

        if (_opEndTime != null) {
          final current = c.value.position;
          if (current < _opEndTime! && current > const Duration(seconds: 2)) {
            if (!_showSkipOpBtn) setState(() => _showSkipOpBtn = true);
          } else {
            if (_showSkipOpBtn) setState(() => _showSkipOpBtn = false);
          }
        }
      });

      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (c.value.isInitialized) {
          prefs.setInt(_progressKey, c.value.position.inMilliseconds);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '媒体流解析失败：可能受 DRM 保护或设备解码器不支持。\n($e)';
          _loading = false;
          _isWebViewMode = true;
        });
        
        // 核心机制：HLS流解析失败回退弹窗
        if (e is PlatformException || e.toString().contains('Unrecognized') || e.toString().contains('Codec')) {
          _showFallbackDialog(_resolvedUrl ?? url, e.toString());
        }
      }
    }
  }

  // 核心功能：外部播放器降级诊断弹窗
  void _showFallbackDialog(String url, String errorReason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('无法使用内置播放器播放'),
        content: Text('诊断信息：$errorReason\n\n当前设备的硬件解码器不支持该视频格式，或者该流受 DRM 保护。\n是否尝试用外部播放器打开？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openExternal(url);
            }, 
            child: const Text('用外部播放器打开')
          ),
        ],
      ),
    );
  }

  void _handleSniffedUrl(String url, InAppWebViewController controller) async {
    if (url.isEmpty || !url.startsWith('http')) return;
    if (!url.contains('.mp4') && !url.contains('.m3u8')) return;
    if (url.startsWith('blob:') || url.startsWith('data:')) return;

    if (!_sniffedUrls.contains(url)) {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(url));
      if (cookies.isNotEmpty) {
        _webViewCookies = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }

      setState(() {
        _sniffedUrls.add(url);
      });
    }
  }

  Future<void> _showChangeSourceSheet() async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final allRules = await _storage.loadRules();
    final otherRules = allRules.where((r) => r.id != widget.rule.id).toList();
    
    if (otherRules.isEmpty) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无其他可用规则')));
      }
      return;
    }

    List<SearchResult> results = [];
    final futures = otherRules.map((rule) async {
      try {
        final res = await _xpath.search(rule, widget.animeTitle);
        if (res.isNotEmpty) results.addAll(res);
      } catch (_) {}
    });
    
    await Future.wait(futures);
    if (!mounted) return;
    Navigator.pop(context);

    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('其他源未找到该番剧')));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Column(
          children: [
            AppBar(
              title: const Text('选择其他源播放'),
              automaticallyImplyLeading: false,
              actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))],
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = results[i];
                  return ListTile(
                    title: Text(r.title),
                    subtitle: Text(r.rule.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailPage(rule: r.rule, detailUrl: r.link, title: r.title),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadSubtitleFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['srt', 'vtt']);
      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      final content = await file.readAsString(encoding: utf8);
      final List<SubtitleItem> parsed = [];
      final blocks = content.split(RegExp(r'\n\s*\n'));
      for (var block in blocks) {
        final lines = block.trim().split('\n');
        if (lines.length >= 3) {
          final times = lines[1].split(' --> ');
          if (times.length == 2) {
            final start = _parseTime(times[0]);
            final end = _parseTime(times[1]);
            if (start != null && end != null) parsed.add(SubtitleItem(start, end, lines.sublist(2).join('\n')));
          }
        }
      }
      setState(() { _subtitles = parsed; _subtitleEnabled = true; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功加载 ${parsed.length} 条字幕')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('字幕加载失败: $e')));
    }
  }

  Duration? _parseTime(String timeStr) {
    timeStr = timeStr.replaceAll(',', '.').trim();
    final parts = timeStr.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final sParts = parts[2].split('.');
      final s = int.tryParse(sParts[0]) ?? 0;
      final ms = sParts.length > 1 ? int.tryParse(sParts[1].padRight(3, '0').substring(0, 3)) ?? 0 : 0;
      return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
    }
    return null;
  }

  // 手势控制
  void _onDoubleTap() { if (_controller == null) return; if (_controller!.value.isPlaying) { _controller!.pause(); _showTip('暂停'); } else { _controller!.play(); _showTip('播放'); } }
  void _onLongPressStart(LongPressStartDetails details) { if (_controller == null) return; _controller!.setPlaybackSpeed(2.0); _showTip('2x 倍速中'); }
  void _onLongPressEnd(LongPressEndDetails details) { if (_controller == null) return; _controller!.setPlaybackSpeed(_playbackSpeed); setState(() => _gestureTip = null); _gestureTipTimer?.cancel(); }
  void _onHorizontalDragStart(DragStartDetails details) { if (_controller == null) return; _dragStartX = details.localPosition.dx; _dragStartPosition = _controller!.value.position; _isDragging = true; _gestureTipTimer?.cancel(); }
  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || _controller == null) return;
    final deltaX = details.localPosition.dx - _dragStartX;
    final seekSeconds = (deltaX / MediaQuery.of(context).size.width) * 600;
    final newPosition = _dragStartPosition + Duration(seconds: seekSeconds.toInt());
    final targetPos = newPosition > Duration.zero && newPosition < _controller!.value.duration ? newPosition : (newPosition <= Duration.zero ? Duration.zero : _controller!.value.duration);
    setState(() => _gestureTip = '${seekSeconds > 0 ? "快进" : "快退"} ${_formatDuration(targetPos)}');
  }
  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isDragging || _controller == null) return;
    _isDragging = false;
    if (_gestureTip != null && _gestureTip!.contains('快')) {
      final parts = _gestureTip!.split(' ').last.split(':');
      if (parts.length == 2) _controller!.seekTo(Duration(minutes: int.tryParse(parts[0]) ?? 0, seconds: int.tryParse(parts[1]) ?? 0));
    }
    _gestureTipTimer?.cancel();
    setState(() => _gestureTip = null);
  }
  void _onVerticalDragStart(DragStartDetails details) {
    if (_controller == null) return;
    _dragStartY = details.localPosition.dy;
    _isDragging = true;
    _gestureTipTimer?.cancel();
    if (details.localPosition.dx < MediaQuery.of(context).size.width / 2) ScreenBrightness().current.then((val) => _startBrightness = val);
    else VolumeController.instance.getVolume().then((val) => _startVolume = val);
  }
  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || _controller == null) return;
    final ratio = (_dragStartY - details.localPosition.dy) / (MediaQuery.of(context).size.height / 2);
    if (details.localPosition.dx < MediaQuery.of(context).size.width / 2) {
      double newVal = (_startBrightness + ratio).clamp(0.0, 1.0);
      ScreenBrightness().setScreenBrightness(newVal);
      setState(() => _gestureTip = '亮度 ${(newVal * 100).toInt()}%');
    } else {
      double newVal = (_startVolume + ratio).clamp(0.0, 1.0);
      VolumeController.instance.setVolume(newVal);
      setState(() => _gestureTip = '音量 ${(newVal * 100).toInt()}%');
    }
  }
  void _onVerticalDragEnd(DragEndDetails details) { _isDragging = false; _gestureTipTimer?.cancel(); setState(() => _gestureTip = null); }

  // 投屏
  Future<void> _castToDevice() async {
    if (_resolvedUrl == null) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final searcher = DLNAManager();
    try {
      final manager = await searcher.start();
      final Map<String, DLNADevice> deviceMap = {};
      final subscription = manager.devices.stream.listen((deviceList) => deviceList.forEach((key, value) => deviceMap[key] = value));
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      Navigator.pop(context);
      searcher.stop();
      await subscription.cancel();
      
      if (deviceMap.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到局域网内的投屏设备')));
        return;
      }
      
      showModalBottomSheet(
        context: context,
        builder: (ctx) => ListView.builder(
          itemCount: deviceMap.length,
          itemBuilder: (_, i) {
            final device = deviceMap.values.elementAt(i);
            return ListTile(
              leading: const Icon(Icons.tv),
              title: Text(device.info.friendlyName),
              onTap: () async {
                Navigator.pop(ctx);
                showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
                try {
                  await device.setUrl(_resolvedUrl!, title: widget.title);
                  await device.play();
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已推送到电视')));
                    _controller?.pause();
                  }
                } catch (e) {
                  if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('投屏失败: $e'))); }
                }
              },
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索设备失败: $e'))); }
    }
  }

  // OP / 弹幕 / 播放速度
  Future<void> _markOpEnd() async {
    if (_controller == null) return;
    final current = _controller!.value.position;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_opKey, current.inMilliseconds);
    setState(() => _opEndTime = current);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已记录片头结束点：${_formatDuration(current)}')));
  }

  Future<void> _showDanmakuSettings() async {
    final textController = TextEditingController(text: _blockWords.join(', '));
    double tempOpacity = _danmakuOpacity;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('弹幕设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: textController, decoration: const InputDecoration(labelText: '屏蔽词 (逗号分隔)')),
              const SizedBox(height: 16),
              Row(children: [const Text('透明度'), Expanded(child: Slider(value: tempOpacity, min: 0.2, max: 1.0, onChanged: (v) => setDialogState(() => tempOpacity = v)))]),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () async {
              final words = textController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setStringList('danmaku_block_words', words);
              await prefs.setDouble('danmaku_opacity', tempOpacity);
              setState(() { _blockWords = words; _danmakuOpacity = tempOpacity; });
              if (ctx.mounted) Navigator.pop(ctx);
            }, child: const Text('保存')),
          ],
        ),
      ),
    );
  }

  Future<void> _loadDanmakus() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_danmakuKey);
    if (data != null) {
      try {
        final List<dynamic> list = jsonDecode(data);
        if (mounted) setState(() => _danmakus = list.map((e) => DanmakuItem(text: e['text'], time: Duration(milliseconds: e['time']), color: Colors.white)).toList());
      } catch (_) {}
    }
  }

  Future<void> _saveDanmakus() async {
    final prefs = await SharedPreferences.getInstance();
    _danmakus.sort((a, b) => a.time.compareTo(b.time));
    await prefs.setString(_danmakuKey, jsonEncode(_danmakus.map((e) => {'text': e.text, 'time': e.time.inMilliseconds}).toList()));
  }

  Future<void> _sendDanmaku() async {
    final text = _danmakuController.text.trim();
    if (text.isEmpty || _controller == null) return;
    setState(() { _danmakus.add(DanmakuItem(text: text, time: _controller!.value.position)); _showDanmakuInput = false; _danmakuController.clear(); });
    await _saveDanmakus();
    FocusScope.of(context).unfocus();
  }

  Future<void> _importDanmaku() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      if (await file.length() > 10 * 1024 * 1024) throw Exception('文件过大，最大支持 10MB');
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) throw Exception('JSON 格式错误，必须是数组');
      int importCount = 0; int skipCount = 0;
      for (var item in decoded) {
        try {
          if (item is Map && item['time'] != null && item['text'] != null) {
            int ms = (item['time'] is double) ? (item['time'] * 1000).toInt() : (item['time'] as num).toInt();
            _danmakus.add(DanmakuItem(text: item['text'].toString(), time: Duration(milliseconds: ms)));
            importCount++;
          } else { skipCount++; }
        } catch (_) { skipCount++; }
      }
      await _saveDanmakus();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功导入 $importCount 条弹幕！${skipCount > 0 ? " (跳过 $skipCount 条无效数据)" : ""}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _shareScreenshot() async {
    try {
      final boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final file = File('${(await getTemporaryDirectory()).path}/anime_share_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: '我在看《${widget.animeTitle}》- ${widget.title}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('截图失败: $e')));
    }
  }

  bool _isDirectVideo(String url) {
    try {
      final path = Uri.parse(url).path.toLowerCase();
      return path.endsWith('.mp4') || path.endsWith('.m3u8') || path.endsWith('.webm') || path.endsWith('.mkv') || path.endsWith('.flv') || path.endsWith('.m4v');
    } catch (_) { return false; }
  }

  void _setSpeed(double speed) async {
    if (_controller != null) {
      _controller!.setPlaybackSpeed(speed);
      setState(() => _playbackSpeed = speed);
      await (await SharedPreferences.getInstance()).setDouble('playback_speed', speed);
    }
  }

  void _startSleepTimer(int minutes) {
    _sleepTimer?.cancel(); _sleepTimer = null;
    if (minutes == 0) { setState(() => _sleepMinutesRemaining = 0); return; }
    setState(() => _sleepMinutesRemaining = minutes);
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_sleepMinutesRemaining <= 1) {
        _sleepTimer?.cancel(); _sleepTimer = null; _controller?.pause();
        if (mounted) { setState(() => _sleepMinutesRemaining = 0); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('定时关闭已生效，视频已暂停'))); }
      } else { if (mounted) setState(() => _sleepMinutesRemaining--); }
    });
  }

  @override
  void dispose() {
    _sleepTimer?.cancel(); 
    _gestureTipTimer?.cancel(); 
    _progressTimer?.cancel(); 
    _danmakuController.dispose();
    
    if (_controller != null && _controller!.value.isInitialized) {
       SharedPreferences.getInstance().then((prefs) => prefs.setInt(_progressKey, _controller!.value.position.inMilliseconds));
    }
    
    _controller?.removeListener(() {}); 
    _controller?.dispose(); 
    _controller = null; // 核心修复：显式置空，避免 State 回收后 VideoPlayer 仍在后台绘制
    
    ScreenBrightness().resetScreenBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.swap_horiz), tooltip: '一键换源', onPressed: _showChangeSourceSheet),
          if (_controller != null && _controller!.value.isInitialized) ...[
            IconButton(icon: const Icon(Icons.subtitles), tooltip: '加载字幕', onPressed: _loadSubtitleFile),
            IconButton(icon: const Icon(Icons.screenshot_monitor), tooltip: '投屏', onPressed: _castToDevice),
            IconButton(icon: const Icon(Icons.camera_alt_outlined), tooltip: '截图分享', onPressed: _shareScreenshot),
          ],
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'import_danmaku') _importDanmaku();
              else if (value == 'danmaku_settings') _showDanmakuSettings();
              else if (value == 'mark_op') _markOpEnd();
              else if (value.startsWith('sleep_')) _startSleepTimer(int.parse(value.split('_')[1]));
              else if (value == 'open_external' && _resolvedUrl != null) _openExternal(_resolvedUrl!);
            },
            itemBuilder: (context) => [
              if (_controller == null || !_controller!.value.isInitialized)
                const PopupMenuItem(value: 'open_external', child: Text('🌐 用外部浏览器打开')),
              if (_controller != null && _controller!.value.isInitialized) ...[
                const PopupMenuItem(value: 'mark_op', child: Text('📍 记录当前为片头结束')),
                const PopupMenuItem(value: 'danmaku_settings', child: Text('⚙️ 弹幕设置(屏蔽词/透明度)')),
                const PopupMenuItem(value: 'import_danmaku', child: Text('📥 导入本地弹幕 (JSON)')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'sleep_15', child: Text('15分钟后暂停')),
                const PopupMenuItem(value: 'sleep_30', child: Text('30分钟后暂停')),
                const PopupMenuItem(value: 'sleep_60', child: Text('60分钟后暂停')),
                const PopupMenuItem(value: 'sleep_0', child: Text('取消定时')),
              ],
            ],
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('解析提示：$_error', style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: () => _openExternal(_resolvedUrl ?? widget.episodeUrl), child: const Text('用外部浏览器打开')),
                      ],
                    ),
                  )
                : _isWebViewMode
                    ? _buildWebViewPlayer()
                    : _controller != null && _controller!.value.isInitialized
                        ? _buildVideoPlayer()
                        : const Text('加载中...', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildWebViewPlayer() {
    if (_resolvedUrl == null) return const Text('找不到播放地址', style: TextStyle(color: Colors.white));
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_resolvedUrl!)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            useHybridComposition: true,
          ),
          onLoadResource: (controller, resource) {
            final url = resource.url.toString();
            _handleSniffedUrl(url, controller);
          },
        ),
        
        if (_sniffedUrls.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.deepPurpleAccent,
              borderRadius: BorderRadius.circular(8),
              elevation: 4,
              child: InkWell(
                onTap: () {
                  String bestUrl = _sniffedUrls.first;
                  for (var u in _sniffedUrls) {
                    if (u.contains('.m3u8')) { bestUrl = u; break; }
                  }
                  _initPlayer(bestUrl);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_fill, color: Colors.white),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '已捕获到视频媒体流\n点击使用内置播放器无缝播放',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoPlayer() {
    return RepaintBoundary(
      key: _globalKey,
      child: GestureDetector(
        onDoubleTap: _onDoubleTap,
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: _onLongPressEnd,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!)),
            if (_subtitleEnabled && _currentSubtitleText != null && _currentSubtitleText!.isNotEmpty)
              Positioned(bottom: 80, left: 20, right: 20, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: Text(_currentSubtitleText!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 2, offset: Offset(1, 1))])))),
            if (_showSkipOpBtn && _opEndTime != null)
              Positioned(right: 16, bottom: 120, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), onPressed: () { _controller!.seekTo(_opEndTime!); setState(() => _showSkipOpBtn = false); }, child: Text('跳过片头 ${_formatDuration(_opEndTime! - _controller!.value.position)}'))),
            if (_danmakuEnabled)
              DanmakuOverlay(currentPosition: _controller!.value.position, danmakus: _danmakus, isPlaying: _controller!.value.isPlaying, blockWords: _blockWords, opacity: _danmakuOpacity),
            if (_gestureTip != null)
              Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(8)), child: Text(_gestureTip!, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black87], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_controller!.value.duration.inSeconds > 0) DanmakuHeatmap(danmakus: _danmakus, totalDuration: _controller!.value.duration, currentPosition: _controller!.value.position),
                    if (_showDanmakuInput)
                      Row(children: [Expanded(child: TextField(controller: _danmakuController, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: '发一条友善的弹幕...', hintStyle: TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white12, border: OutlineInputBorder(borderSide: BorderSide.none), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onSubmitted: (_) => _sendDanmaku())), IconButton(icon: const Icon(Icons.send, color: Colors.deepPurpleAccent), onPressed: _sendDanmaku)]),
                    VideoProgressIndicator(_controller!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Colors.deepPurpleAccent)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(children: [IconButton(icon: Icon(_controller!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white), onPressed: () { setState(() { _controller!.value.isPlaying ? _controller!.pause() : _controller!.play(); }); }), IconButton(icon: const Icon(Icons.chat_bubble_outline, color: Colors.white), onPressed: () { setState(() => _showDanmakuInput = !_showDanmakuInput); }), Text('${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}', style: const TextStyle(color: Colors.white, fontSize: 12))]),
                        Row(children: [0.5, 1.0, 1.5, 2.0].map((speed) { return GestureDetector(onTap: () => _setSpeed(speed), child: Container(margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: _playbackSpeed == speed ? Colors.deepPurple : Colors.white24, borderRadius: BorderRadius.circular(4)), child: Text('${speed}x', style: const TextStyle(color: Colors.white, fontSize: 12)))); }).toList()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }
}

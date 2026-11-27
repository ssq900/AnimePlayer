import 'dart:async';
import 'dart:collection';
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
import 'package:video_player/video_player.dart'; // 核心修复：补全这个引入
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:dlna_dart/dlna.dart'; 
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/rule.dart';
import '../services/xpath_service.dart';
import '../services/storage_service.dart';
import '../services/playback_engine.dart';
import '../services/fallback_manager.dart';
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
  final _engine = PlaybackEngine();
  FallbackManager? _fallbackManager;
  
  final GlobalKey _globalKey = GlobalKey();

  bool _loading = true;
  String? _resolvedUrl;
  String? _error;
  bool _isFallbacking = false;
  
  Set<String> _sniffedUrls = {}; 
  bool _isWebViewMode = false; 
  String? _webViewCookies; 

  double _playbackSpeed = 1.0;
  Timer? _sleepTimer;
  Timer? _progressTimer;
  int _sleepMinutesRemaining = 0;

  List<DanmakuItem> _danmakus = [];
  final _danmakuController = TextEditingController();
  bool _showDanmakuInput = false;
  bool _danmakuEnabled = true;
  List<String> _blockWords = [];
  double _danmakuOpacity = 1.0;
  Duration? _opEndTime;
  bool _showSkipOpBtn = false;
  List<SubtitleItem> _subtitles = [];
  String? _currentSubtitleText;
  bool _subtitleEnabled = true;

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
    _engine.errorStream.listen(_handlePlaybackError);
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
        ruleId: widget.rule.id, ruleName: widget.rule.name,
        animeTitle: widget.animeTitle, episodeTitle: widget.title,
        episodeUrl: widget.episodeUrl, timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await _loadDanmakus();

      // 初始化 Fallback 候选池
      try {
        final allRules = await _storage.loadRules();
        final otherRules = allRules.where((r) => r.id != widget.rule.id).toList();
        List<SearchResult> candidates = [SearchResult(title: widget.title, link: url, rule: widget.rule)];
        
        for (var r in otherRules) {
          _xpath.search(r, widget.animeTitle).then((res) {
             if(res.isNotEmpty) candidates.addAll(res);
          }).catchError((_) {});
        }
        _fallbackManager = FallbackManager(candidates, maxRetries: 2);
      } catch (_) {}

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

      await _engine.open(url, headers: headers);
      
      if (!mounted) return;
      setState(() => _loading = false);
      _engine.setPlaybackSpeed(_playbackSpeed);
      
      final prefs = await SharedPreferences.getInstance();
      final savedMs = prefs.getInt(_progressKey) ?? 0;
      if (savedMs > 5000 && savedMs < _engine.controller!.value.duration.inMilliseconds - 10000) {
        _engine.seek(Duration(milliseconds: savedMs));
        _showTip('已为您续播至 ${_formatDuration(Duration(milliseconds: savedMs))}');
      }
      
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (_engine.isInitialized) {
          prefs.setInt(_progressKey, _engine.controller!.value.position.inMilliseconds);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '媒体流解析失败：可能受 DRM 保护或需要高级鉴权。\n($e)';
          _loading = false;
          _isWebViewMode = true;
        });
      }
    }
  }

  void _handlePlaybackError(PlaybackError error) async {
    if (!mounted || _fallbackManager == null) return;
    
    if (_fallbackManager!.shouldFallback(error)) {
      setState(() => _isFallbacking = true);
      _showTip('当前源不可用，正在尝试自动切换...');
      
      final nextMedia = _fallbackManager!.getNextCandidate(_resolvedUrl ?? '');
      if (nextMedia != null) {
        _resolvedUrl = nextMedia.link;
        await _initPlayer(nextMedia.link);
        if (mounted) setState(() => _isFallbacking = false);
      } else {
        setState(() {
          _isFallbacking = false;
          _loading = false;
        });
        _showFallbackSourceDialog();
      }
    }
  }

  void _showFallbackSourceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('播放失败'),
        content: const Text('当前设备解码器不支持该格式，或者所有备用源均失效。是否尝试外部播放器或手动换源？'),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(ctx); _openExternal(_resolvedUrl!); },
            child: const Text('外部打开'),
          ),
          FilledButton(
            onPressed: () { Navigator.pop(ctx); _showChangeSourceSheet(); },
            child: const Text('手动换源'),
          ),
        ],
      ),
    );
  }

  final String _sniffJs = """
    (function() {
        var origXhr = window.XMLHttpRequest.prototype.open;
        window.XMLHttpRequest.prototype.open = function(method, url) {
            if (url && typeof url === 'string' && (url.includes('.m3u8') || url.includes('.mp4'))) {
                window.flutter_inappwebview.callHandler('jsSniffed', url);
            }
            return origXhr.apply(this, arguments);
        };
        var origFetch = window.fetch;
        window.fetch = function(input) {
            var url = typeof input === 'string' ? input : (input ? input.url : '');
            if (url && (url.includes('.m3u8') || url.includes('.mp4'))) {
                window.flutter_inappwebview.callHandler('jsSniffed', url);
            }
            return origFetch.apply(this, arguments);
        };
        var observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(m) {
                if (m.target.tagName === 'VIDEO' && m.target.src && m.target.src.includes('.m3u8')) {
                    window.flutter_inappwebview.callHandler('jsSniffed', m.target.src);
                }
            });
        });
        observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
    })();
  """;

  void _handleSniffedUrl(String url) async {
    if (url.isEmpty || !url.startsWith('http') || url.startsWith('blob:') || url.startsWith('data:')) return;
    
    if (!_sniffedUrls.contains(url)) {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(url));
      if (cookies.isNotEmpty) {
        _webViewCookies = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
      if (mounted) setState(() => _sniffedUrls.add(url));
    }
  }

  bool _handleNativeIntercept(WebResourceRequest request) {
    final url = request.url.toString();
    _handleSniffedUrl(url);
    return false;
  }

  // ==================== 手势与交互逻辑 ====================

  void _onDoubleTap() { if (!_engine.isInitialized) return; if (_engine.isPlaying) { _engine.pause(); _showTip('暂停'); } else { _engine.play(); _showTip('播放'); } }
  void _onLongPressStart(LongPressStartDetails details) { if (!_engine.isInitialized) return; _engine.setPlaybackSpeed(2.0); _showTip('2x 倍速中'); }
  void _onLongPressEnd(LongPressEndDetails details) { if (!_engine.isInitialized) return; _engine.setPlaybackSpeed(_playbackSpeed); setState(() => _gestureTip = null); _gestureTipTimer?.cancel(); }
  void _onHorizontalDragStart(DragStartDetails details) { if (!_engine.isInitialized) return; _dragStartX = details.localPosition.dx; _dragStartPosition = _engine.controller!.value.position; _isDragging = true; _gestureTipTimer?.cancel(); }
  
  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || !_engine.isInitialized) return;
    final deltaX = details.localPosition.dx - _dragStartX;
    final seekSeconds = (deltaX / MediaQuery.of(context).size.width) * 600;
    final newPosition = _dragStartPosition + Duration(seconds: seekSeconds.toInt());
    final targetPos = newPosition > Duration.zero && newPosition < _engine.controller!.value.duration ? newPosition : (newPosition <= Duration.zero ? Duration.zero : _engine.controller!.value.duration);
    setState(() => _gestureTip = '${seekSeconds > 0 ? "快进" : "快退"} ${_formatDuration(targetPos)}');
  }
  
  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isDragging || !_engine.isInitialized) return;
    _isDragging = false;
    if (_gestureTip != null && _gestureTip!.contains('快')) {
      final parts = _gestureTip!.split(' ').last.split(':');
      if (parts.length == 2) _engine.seek(Duration(minutes: int.tryParse(parts[0]) ?? 0, seconds: int.tryParse(parts[1]) ?? 0));
    }
    _gestureTipTimer?.cancel();
    setState(() => _gestureTip = null);
  }
  
  void _onVerticalDragStart(DragStartDetails details) {
    if (!_engine.isInitialized) return;
    _dragStartY = details.localPosition.dy;
    _isDragging = true;
    _gestureTipTimer?.cancel();
    if (details.localPosition.dx < MediaQuery.of(context).size.width / 2) ScreenBrightness().current.then((val) => _startBrightness = val);
    else VolumeController.instance.getVolume().then((val) => _startVolume = val);
  }
  
  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || !_engine.isInitialized) return;
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

  // ==================== 辅助功能 ====================

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
                    _engine.pause();
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

  Future<void> _markOpEnd() async {
    if (!_engine.isInitialized) return;
    final current = _engine.controller!.value.position;
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
    if (text.isEmpty || !_engine.isInitialized) return;
    setState(() { _danmakus.add(DanmakuItem(text: text, time: _engine.controller!.value.position)); _showDanmakuInput = false; _danmakuController.clear(); });
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

  bool _isDirectVideo(String url) {
    try {
      final path = Uri.parse(url).path.toLowerCase();
      return path.endsWith('.mp4') || path.endsWith('.m3u8') || path.endsWith('.webm') || path.endsWith('.mkv') || path.endsWith('.flv') || path.endsWith('.m4v');
    } catch (_) { return false; }
  }

  void _setSpeed(double speed) async {
    if (_engine.isInitialized) {
      _engine.setPlaybackSpeed(speed);
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
        _sleepTimer?.cancel(); _sleepTimer = null; _engine.pause();
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
    
    if (_engine.isInitialized) {
       SharedPreferences.getInstance().then((prefs) => prefs.setInt(_progressKey, _engine.controller!.value.position.inMilliseconds));
    }
    _engine.dispose(); 
    
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
          if (_engine.isInitialized) ...[
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
              if (!_engine.isInitialized)
                const PopupMenuItem(value: 'open_external', child: Text('🌐 用外部浏览器打开')),
              if (_engine.isInitialized) ...[
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
        child: _loading || _isFallbacking
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (_isFallbacking) ...[
                    const SizedBox(height: 16),
                    const Text('当前源异常，正在自动切换备用源...', style: TextStyle(color: Colors.white)),
                  ]
                ],
              )
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
                    : _engine.isInitialized
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
          initialUserScripts: UnmodifiableListView([
            UserScript(source: _sniffJs, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START)
          ]),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            useHybridComposition: true,
          ),
          onWebViewCreated: (controller) {
            controller.addJavaScriptHandler(
              handlerName: 'jsSniffed',
              callback: (args) {
                if (args.isNotEmpty) _handleSniffedUrl(args[0].toString());
              },
            );
          },
          shouldInterceptRequest: (controller, request) async {
            _handleNativeIntercept(request);
            return null;
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
    final controller = _engine.controller!;
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
            AspectRatio(
              aspectRatio: controller.value.aspectRatio, 
              child: VideoPlayer(controller), // 核心修复：使用正确的 controller
            ),
            if (_subtitleEnabled && _currentSubtitleText != null && _currentSubtitleText!.isNotEmpty)
              Positioned(bottom: 80, left: 20, right: 20, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: Text(_currentSubtitleText!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 2, offset: Offset(1, 1))])))),
            if (_showSkipOpBtn && _opEndTime != null)
              Positioned(right: 16, bottom: 120, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), onPressed: () { _engine.seek(_opEndTime!); setState(() => _showSkipOpBtn = false); }, child: Text('跳过片头 ${_formatDuration(_opEndTime! - controller.value.position)}'))),
            if (_danmakuEnabled)
              DanmakuOverlay(currentPosition: controller.value.position, danmakus: _danmakus, isPlaying: controller.value.isPlaying, blockWords: _blockWords, opacity: _danmakuOpacity),
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
                    if (controller.value.duration.inSeconds > 0) DanmakuHeatmap(danmakus: _danmakus, totalDuration: controller.value.duration, currentPosition: controller.value.position),
                    if (_showDanmakuInput)
                      Row(children: [Expanded(child: TextField(controller: _danmakuController, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: '发一条友善的弹幕...', hintStyle: TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white12, border: OutlineInputBorder(borderSide: BorderSide.none), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onSubmitted: (_) => _sendDanmaku())), IconButton(icon: const Icon(Icons.send, color: Colors.deepPurpleAccent), onPressed: _sendDanmaku)]),
                    VideoProgressIndicator(
                      controller, 
                      allowScrubbing: true, 
                      colors: const VideoProgressColors(playedColor: Colors.deepPurpleAccent), // 去掉了之前的编译错误
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(children: [IconButton(icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white), onPressed: () { setState(() { controller.value.isPlaying ? _engine.pause() : _engine.play(); }); }), IconButton(icon: const Icon(Icons.chat_bubble_outline, color: Colors.white), onPressed: () { setState(() => _showDanmakuInput = !_showDanmakuInput); }), Text('${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}', style: const TextStyle(color: Colors.white, fontSize: 12))]),
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

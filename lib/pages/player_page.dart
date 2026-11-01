import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rule.dart';
import '../services/xpath_service.dart';
import '../services/storage_service.dart';
import '../widgets/danmaku_overlay.dart';

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

  VideoPlayerController? _controller;
  bool _loading = true;
  String? _resolvedUrl;
  String? _error;

  double _playbackSpeed = 1.0;
  Timer? _sleepTimer;
  int _sleepMinutesRemaining = 0;

  // 弹幕状态
  List<DanmakuItem> _danmakus = [];
  final _danmakuController = TextEditingController();
  bool _showDanmakuInput = false;
  bool _danmakuEnabled = true;

  // 手势状态
  bool _showControls = true;
  Timer? _hideControlsTimer;
  String? _gestureTip;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _playbackSpeed = prefs.getDouble('playback_speed') ?? 1.0;
    _danmakuEnabled = prefs.getBool('danmaku_enabled') ?? true;
    await _resolve();
  }

  Future<void> _loadDanmakus() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'danmaku_${widget.episodeUrl.hashCode}';
    final data = prefs.getString(key);
    if (data != null) {
      try {
        final List<dynamic> list = jsonDecode(data);
        setState(() {
          _danmakus = list.map((e) => DanmakuItem(
            text: e['text'],
            time: Duration(milliseconds: e['time']),
            color: Colors.white,
          )).toList();
        });
      } catch (_) {}
    }
  }

  Future<void> _saveDanmakus() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'danmaku_${widget.episodeUrl.hashCode}';
    _danmakus.sort((a, b) => a.time.compareTo(b.time));
    final list = _danmakus.map((e) => {'text': e.text, 'time': e.time.inMilliseconds}).toList();
    await prefs.setString(key, jsonEncode(list));
  }

  Future<void> _sendDanmaku() async {
    final text = _danmakuController.text.trim();
    if (text.isEmpty || _controller == null) return;

    final currentTime = _controller!.value.position;
    final newItem = DanmakuItem(text: text, time: currentTime);

    setState(() {
      _danmakus.add(newItem);
      _showDanmakuInput = false;
      _danmakuController.clear();
    });

    await _saveDanmakus();
    FocusScope.of(context).unfocus();
  }

  Future<void> _importDanmaku() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      
      // 修复：限制文件大小不超过 10MB 防 OOM
      if (await file.length() > 10 * 1024 * 1024) {
        throw Exception('文件过大，最大支持 10MB');
      }

      final content = await file.readAsString();
      final List<dynamic> data = jsonDecode(content);
      int importCount = 0;

      for (var item in data) {
        if (item['time'] != null && item['text'] != null) {
          int ms = (item['time'] is double) 
              ? (item['time'] * 1000).toInt() 
              : (item['time'] as num).toInt();
              
          _danmakus.add(DanmakuItem(
            text: item['text'].toString(),
            time: Duration(milliseconds: ms),
          ));
          importCount++;
        }
      }

      await _saveDanmakus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 $importCount 条弹幕！')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败，请检查文件格式: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _resolve() async {
    try {
      final url = await _xpath.resolveEpisodeLink(widget.rule, widget.episodeUrl);
      if (!mounted) return;
      _resolvedUrl = url;

      // 修复：静默忽略 bool 返回值，消除 analyzer 警告
      // ignore: unused_result
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
        final c = VideoPlayerController.networkUrl(Uri.parse(url));
        try {
          await c.initialize();
          if (!mounted) {
            await c.dispose();
            return;
          }
          setState(() => _controller = c);
          c.setPlaybackSpeed(_playbackSpeed);
          c.play();
          
          c.addListener(() {
            if (mounted && _danmakuEnabled) setState(() {});
          });
          
          _startHideControlsTimer();
        } catch (e) {
          await c.dispose();
          throw Exception('视频初始化失败，可能是格式不支持或网络问题。$e');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _resolvedUrl = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isDirectVideo(String url) {
    try {
      final path = Uri.parse(url).path.toLowerCase();
      return path.endsWith('.mp4') || path.endsWith('.m3u8') ||
          path.endsWith('.webm') || path.endsWith('.mkv') ||
          path.endsWith('.flv') || path.endsWith('.m4v');
    } catch (_) {
      return false;
    }
  }

  void _setSpeed(double speed) async {
    if (_controller != null) {
      _controller!.setPlaybackSpeed(speed);
      setState(() => _playbackSpeed = speed);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('playback_speed', speed);
    }
  }

  void _startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepMinutesRemaining = minutes);
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_sleepMinutesRemaining <= 1) {
        timer.cancel();
        _controller?.pause();
        if (mounted) {
          setState(() => _sleepMinutesRemaining = 0);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('定时关闭已生效，视频已暂停')));
        }
      } else {
        if (mounted) setState(() => _sleepMinutesRemaining--);
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _hideControlsTimer?.cancel();
    _danmakuController.dispose();
    _controller?.dispose();
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
          IconButton(
            icon: Icon(_danmakuEnabled ? Icons.subtitles : Icons.subtitles_off),
            onPressed: () async {
              setState(() => _danmakuEnabled = !_danmakuEnabled);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('danmaku_enabled', _danmakuEnabled);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'import_danmaku') {
                _importDanmaku();
                return;
              }
              if (value.startsWith('sleep_')) {
                final min = int.parse(value.split('_')[1]);
                if (min == 0) {
                  _sleepTimer?.cancel();
                  setState(() => _sleepMinutesRemaining = 0);
                } else {
                  _startSleepTimer(min);
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'import_danmaku', child: Text('📥 导入本地弹幕 (JSON)')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'sleep_15', child: Text('15分钟后暂停')),
              const PopupMenuItem(value: 'sleep_30', child: Text('30分钟后暂停')),
              const PopupMenuItem(value: 'sleep_60', child: Text('60分钟后暂停')),
              const PopupMenuItem(value: 'sleep_0', child: Text('取消定时')),
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
                        Text('解析失败：$_error', style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _openExternal(_resolvedUrl ?? widget.episodeUrl),
                          child: const Text('用外部浏览器打开'),
                        ),
                      ],
                    ),
                  )
                : _controller != null && _controller!.value.isInitialized
                    ? _buildVideoPlayer()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_new, size: 48, color: Colors.white),
                          const SizedBox(height: 12),
                          const Text('解析结果为网页，需交给外部应用处理', style: TextStyle(color: Colors.white)),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _openExternal(_resolvedUrl ?? widget.episodeUrl),
                            child: const Text('打开外部页面'),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return GestureDetector(
      onTap: () {
        setState(() => _showControls = !_showControls);
        if (_showControls) _startHideControlsTimer();
      },
      onDoubleTap: () {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
          setState(() => _gestureTip = '暂停');
        } else {
          _controller!.play();
          setState(() => _gestureTip = '播放');
        }
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _gestureTip = null);
        });
      },
      onLongPressStart: (_) {
        _controller!.setPlaybackSpeed(2.0);
        setState(() => _gestureTip = '2x 倍速播放中');
      },
      onLongPressEnd: (_) {
        _controller!.setPlaybackSpeed(_playbackSpeed);
        setState(() => _gestureTip = null);
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
          
          if (_danmakuEnabled)
            DanmakuOverlay(
              currentPosition: _controller!.value.position,
              danmakus: _danmakus,
              isPlaying: _controller!.value.isPlaying,
            ),

          // 手势提示
          if (_gestureTip != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_gestureTip!, style: const TextStyle(color: Colors.white, fontSize: 18)),
            ),

          // 控制层
          if (_showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showDanmakuInput)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _danmakuController,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: '发一条友善的弹幕...',
                                hintStyle: TextStyle(color: Colors.white54),
                                filled: true,
                                fillColor: Colors.white12,
                                border: OutlineInputBorder(borderSide: BorderSide.none),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onSubmitted: (_) => _sendDanmaku(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.send, color: Colors.deepPurpleAccent),
                            onPressed: _sendDanmaku,
                          ),
                        ],
                      ),
                    VideoProgressIndicator(
                      _controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(playedColor: Colors.deepPurpleAccent),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(_controller!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                              onPressed: () {
                                setState(() => _showDanmakuInput = !_showDanmakuInput);
                              },
                            ),
                            Text(
                              '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                        Row(
                          children: [0.5, 1.0, 1.5, 2.0].map((speed) {
                            return GestureDetector(
                              onTap: () => _setSpeed(speed),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _playbackSpeed == speed ? Colors.deepPurple : Colors.white24,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('${speed}x', style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接')));
      }
    }
  }
}

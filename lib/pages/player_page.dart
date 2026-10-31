import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../models/rule.dart';
import '../services/xpath_service.dart';
import '../services/storage_service.dart';

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

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final url = await _xpath.resolveEpisodeLink(widget.rule, widget.episodeUrl);
      if (!mounted) return;
      _resolvedUrl = url;

      // 保存到历史记录
      await _storage.addHistory(HistoryItem(
        ruleId: widget.rule.id,
        ruleName: widget.rule.name,
        animeTitle: widget.animeTitle,
        episodeTitle: widget.title,
        episodeUrl: widget.episodeUrl,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      if (_isDirectVideo(url)) {
        final c = VideoPlayerController.networkUrl(Uri.parse(url));
        await c.initialize();
        if (!mounted) {
          await c.dispose();
          return;
        }
        setState(() => _controller = c);
        c.play();
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

  void _setSpeed(double speed) {
    if (_controller != null) {
      _controller!.setPlaybackSpeed(speed);
      setState(() => _playbackSpeed = speed);
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('定时关闭已生效，视频已暂停')),
          );
        }
      } else {
        if (mounted) setState(() => _sleepMinutesRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_sleepMinutesRemaining > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('$_sleepMinutesRemaining分后停', style: const TextStyle(color: Colors.red)),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
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
              const PopupMenuItem(value: 'sleep_15', child: Text('15分钟后暂停')),
              const PopupMenuItem(value: 'sleep_30', child: Text('30分钟后暂停')),
              const PopupMenuItem(value: 'sleep_60', child: Text('60分钟后暂停')),
              const PopupMenuItem(value: 'sleep_0', child: Text('取消定时')),
            ],
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('解析失败：$_error'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _openExternal(_resolvedUrl ?? widget.episodeUrl),
                          child: const Text('用外部浏览器打开'),
                        ),
                      ],
                    ),
                  )
                : _controller != null && _controller!.value.isInitialized
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [0.5, 1.0, 1.5, 2.0].map((speed) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: ChoiceChip(
                                  label: Text('${speed}x'),
                                  selected: _playbackSpeed == speed,
                                  onSelected: (_) => _setSpeed(speed),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_new, size: 48),
                          const SizedBox(height: 12),
                          const Text('解析结果为网页，需交给外部应用处理'),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _openExternal(_resolvedUrl ?? widget.episodeUrl),
                            child: const Text('打开外部页面'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () async {
                              setState(() => _loading = true);
                              try {
                                final c = VideoPlayerController.networkUrl(Uri.parse(_resolvedUrl ?? widget.episodeUrl));
                                await c.initialize();
                                if (mounted) {
                                  setState(() {
                                    _controller = c;
                                    _loading = false;
                                  });
                                  c.play();
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _loading = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('无法作为直链播放: $e')),
                                  );
                                }
                              }
                            },
                            child: const Text('尝试作为直链播放'),
                          ),
                        ],
                      ),
      ),
    );
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接')),
        );
      }
    }
  }
}

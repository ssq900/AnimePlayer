import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import '../features/player/playback_controller.dart';
import '../models/rule.dart';
import '../widgets/danmaku_overlay.dart';
import '../services/danmaku_provider.dart';

class PlayerPage extends ConsumerStatefulWidget {
  final String? videoUrl;
  final String? episodeUrl;
  final String? title;
  final String? animeTitle;
  final String? episodeTitle;
  final AnimeRule? rule;
  // 预留：如果传了选集列表，可以在这里展示
  final List<EpisodeItem>? episodes; 

  const PlayerPage({
    super.key,
    this.videoUrl,
    this.episodeUrl,
    this.title,
    this.animeTitle,
    this.episodeTitle,
    this.rule,
    this.episodes,
  });

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  List<DanmakuItem> _currentDanmakus = [];
  bool _isLoadingDanmaku = true;

  // UI 控制状态
  bool _showControls = true;
  Timer? _hideControlsTimer;

  // 手势状态
  double _brightness = 1.0;
  double _volume = 0.5;
  double _seekPosition = 0.0;
  String _activeGesture = ''; // 'brightness', 'volume', 'seek'
  bool _isGestureActive = false;
  double _gestureStartX = 0;
  double _gestureStartY = 0;
  Duration _gestureStartPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _loadDanmaku();
    _initSystemUI();
  }

  void _initSystemUI() async {
    _brightness = await ScreenBrightness().current;
    VolumeController.instance.getVolume().then((v) {
      if (mounted) setState(() => _volume = v);
    });
    _startHideControlsTimer();
  }

  void _initPlayer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final url = (widget.videoUrl != null && widget.videoUrl!.isNotEmpty)
          ? widget.videoUrl!
          : (widget.episodeUrl ?? '');
      if (url.isNotEmpty) {
        ref.read(playbackControllerProvider.notifier).initialize(
          url,
          animeTitle: widget.animeTitle ?? widget.title ?? '',
          episodeTitle: widget.episodeTitle ?? '',
          ruleId: widget.rule?.id ?? '',
        );
      }
    });
  }

  Future<void> _loadDanmaku() async {
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _currentDanmakus = List.generate(200, (index) => DanmakuItem(
          time: index * 0.5,
          text: '测试弹幕 $index 号',
          color: index % 3 == 0 ? 0xFF0000 : 0xFFFFFF,
          type: index % 10 == 0 ? 1 : 0,
        ));
        _isLoadingDanmaku = false;
      });
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  // ================= 手势处理 =================
  void _onGestureStart(DragStartDetails details) {
    final width = MediaQuery.of(context).size.width;
    _gestureStartX = details.globalPosition.dx;
    _gestureStartY = details.globalPosition.dy;
    _gestureStartPosition = ref.read(playbackControllerProvider).position;

    if (_gestureStartX < width / 3) {
      _activeGesture = 'brightness';
    } else if (_gestureStartX > width * 2 / 3) {
      _activeGesture = 'volume';
    } else {
      _activeGesture = 'seek';
    }
    setState(() => _isGestureActive = true);
  }

  void _onGestureUpdate(DragUpdateDetails details) {
    if (!_isGestureActive) return;
    final dy = details.globalPosition.dy - _gestureStartY;
    final dx = details.globalPosition.dx - _gestureStartX;

    if (_activeGesture == 'brightness') {
      _brightness -= dy / 200;
      _brightness = _brightness.clamp(0.0, 1.0);
      ScreenBrightness().setScreenBrightness(_brightness);
      setState(() {});
    } else if (_activeGesture == 'volume') {
      _volume -= dy / 200;
      _volume = _volume.clamp(0.0, 1.0);
      VolumeController.instance.setVolume(_volume);
      setState(() {});
    } else if (_activeGesture == 'seek') {
      final controller = ref.read(playbackControllerProvider).controller;
      if (controller == null) return;
      final duration = controller.value.duration;
      final deltaMs = (dx / MediaQuery.of(context).size.width) * duration.inMilliseconds * 1.5;
      final newPos = _gestureStartPosition + Duration(milliseconds: deltaMs.toInt());
      _seekPosition = (newPos.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
      setState(() {});
    }
  }

  void _onGestureEnd(DragEndDetails details) {
    if (_activeGesture == 'seek') {
      final controller = ref.read(playbackControllerProvider).controller;
      if (controller != null) {
        final duration = controller.value.duration;
        final targetMs = (duration.inMilliseconds * _seekPosition).toInt();
        controller.seekTo(Duration(milliseconds: targetMs));
      }
    }
    setState(() => _isGestureActive = false);
    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    ScreenBrightness().resetScreenBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackControllerProvider);

    if (!state.isInitialized || state.controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final controller = state.controller!;
    final aspect = controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9;

    return Scaffold(
      backgroundColor: Colors.black,
      // 🔥 侧边栏：选集
      endDrawer: _buildEpisodeDrawer(),
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTap: () {
          if (controller.value.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
        },
        onPanStart: _onGestureStart,
        onPanUpdate: _onGestureUpdate,
        onPanEnd: _onGestureEnd,
        child: Stack(
          children: [
            // 1. 视频层
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(controller),
              ),
            ),
            // 2. 弹幕层
            Positioned.fill(
              child: _isLoadingDanmaku
                  ? const SizedBox()
                  : DanmakuOverlay(
                      danmakus: _currentDanmakus,
                      currentPosition: state.position.inMilliseconds / 1000.0,
                      isPlaying: state.isPlaying,
                      playbackSpeed: state.playbackSpeed,
                    ),
            ),
            // 3. 沉浸式控制层
            if (_showControls) _buildControlsLayer(context, state),
            // 4. 手势居中反馈层
            if (_isGestureActive && _activeGesture != 'seek') _buildGestureHUD(),
            // 5. 快进反馈（底部）
            if (_isGestureActive && _activeGesture == 'seek') _buildSeekHUD(controller),
          ],
        ),
      ),
    );
  }

  // ================= UI 组件构建 =================

  Widget _buildControlsLayer(BuildContext context, PlaybackState state) {
    return Container(
      color: Colors.black26,
      child: Stack(
        children: [
          // 顶部返回与标题
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.animeTitle ?? widget.title ?? '正在播放',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.list, color: Colors.white),
                    onPressed: () {
                      Scaffold.of(context).openEndDrawer();
                      _startHideControlsTimer();
                    },
                  ),
                ],
              ),
            ),
          ),
          // 中央播放/暂停
          Center(
            child: IconButton(
              iconSize: 64,
              icon: Icon(
                state.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: Colors.white70,
              ),
              onPressed: () {
                if (state.isPlaying) {
                  state.controller!.pause();
                } else {
                  state.controller!.play();
                }
                _startHideControlsTimer();
              },
            ),
          ),
          // 底部进度条及时间
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                  VideoProgressIndicator(
                    state.controller!,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(playedColor: Colors.redAccent, bufferedColor: Colors.white38, backgroundColor: Colors.white12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_formatDuration(state.position)} / ${_formatDuration(state.duration)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      Text(
                        '${state.playbackSpeed}x',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
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

  Widget _buildGestureHUD() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _activeGesture == 'volume' ? Icons.volume_up : Icons.brightness_6,
              color: Colors.white,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              '${(_activeGesture == 'volume' ? _volume * 100 : _brightness * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekHUD(VideoPlayerController controller) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(bottom: 80),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
        child: Text(
          _formatDuration(Duration(milliseconds: (controller.value.duration.inMilliseconds * _seekPosition).toInt())),
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildEpisodeDrawer() {
    final eps = widget.episodes ?? [];
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选集', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: eps.isEmpty
                  ? const Center(child: Text('暂无剧集信息', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: eps.length,
                      itemBuilder: (context, index) {
                        final ep = eps[index];
                        final isCurrent = ep.title == widget.episodeTitle;
                        return ListTile(
                          title: Text(
                            ep.title,
                            style: TextStyle(color: isCurrent ? Colors.redAccent : Colors.white),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            // TODO: 切换视频源的逻辑
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

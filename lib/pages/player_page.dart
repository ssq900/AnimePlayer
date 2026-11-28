import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
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

  const PlayerPage({
    super.key, 
    this.videoUrl, 
    this.episodeUrl, 
    this.title, 
    this.animeTitle, 
    this.episodeTitle, 
    this.rule
  });

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  List<DanmakuItem> _currentDanmakus = [];
  bool _isLoadingDanmaku = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final url = (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) 
          ? widget.videoUrl! 
          : (widget.episodeUrl ?? '');
      
      if (url.isNotEmpty) {
        ref.read(playbackControllerProvider.notifier).initialize(url);
      }
    });
    _loadDanmaku();
  }

  Future<void> _loadDanmaku() async {
    // 模拟网络请求加载弹幕
    await Future.delayed(const Duration(seconds: 1)); 
    if (mounted) {
      setState(() {
        _currentDanmakus = _generateMockData();
        _isLoadingDanmaku = false;
      });
    }
  }

  // 生成测试弹幕
  List<DanmakuItem> _generateMockData() {
    return List.generate(200, (index) => DanmakuItem(
      time: index * 0.5,
      text: '测试弹幕 $index 号，Canvas 渲染不卡顿',
      color: index % 3 == 0 ? 0xFF0000 : 0xFFFFFF,
      type: index % 10 == 0 ? 1 : 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackControllerProvider);
    final notifier = ref.read(playbackControllerProvider.notifier);

    if (!state.isInitialized || state.controller == null) {
      return Scaffold(
        backgroundColor: Colors.black, 
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: const [
              CircularProgressIndicator(), 
              SizedBox(height: 16), 
              Text('正在初始化...', style: TextStyle(color: Colors.white70))
            ]
          )
        )
      );
    }

    final controller = state.controller!;
    final aspect = controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          final delta = details.primaryDelta ?? 0;
          if (details.globalPosition.dx < MediaQuery.of(context).size.width / 2) { 
            notifier.setBrightness(state.brightness - delta / 200); 
          } else { 
            notifier.setVolume(state.volume - delta / 200); 
          }
        },
        onHorizontalDragUpdate: (details) {
          final delta = details.primaryDelta ?? 0;
          controller.seekTo(state.position + Duration(milliseconds: (delta * 100).round()));
        },
        onDoubleTap: () { 
          if (controller.value.isPlaying) { 
            controller.pause(); 
          } else { 
            controller.play(); 
          } 
        },
        child: Stack(
          children: [
            // 1. 视频层
            Center(
              child: AspectRatio(
                aspectRatio: aspect, 
                child: VideoPlayer(controller)
              )
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
            
            // 3. 进度条
            Positioned(
              bottom: 0, 
              left: 0, 
              right: 0, 
              child: VideoProgressIndicator(
                controller, 
                allowScrubbing: true, 
                colors: const VideoProgressColors(playedColor: Colors.red)
              )
            ),
          ],
        ),
      ),
    );
  }
}

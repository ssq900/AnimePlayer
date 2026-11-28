import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../features/player/playback_controller.dart';
import '../models/rule.dart';
import '../widgets/danmaku_overlay.dart'; // 🔥 引入我们刚写的弹幕层

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
    this.rule,
  });

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
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
  }

  // 🔥 生成测试弹幕的数据源
  List<DanmakuItem> _mockDanmakus() {
    // 生成 200 条测试弹幕
    return List.generate(200, (index) {
      return DanmakuItem(
        time: index * 0.5, // 每 0.5 秒发一条
        text: '测试弹幕 $index 号，Canvas 高性能渲染',
        color: index % 3 == 0 ? 0xFF0000 : 0xFFFFFF, // 部分红色，部分白色
        type: index % 10 == 0 ? 1 : 0, // 每 10 条发一条顶部固定弹幕
      );
    });
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
              Text('正在初始化...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
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
          final newPos = state.position + Duration(milliseconds: (delta * 100).round());
          controller.seekTo(newPos);
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
            // 1. 视频渲染层
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(controller),
              ),
            ),
            
            // 2. Canvas 弹幕层 (挂载在这里，接收播放器状态)
            Positioned.fill(
              child: DanmakuOverlay(
                danmakus: _mockDanmakus(), // 注入测试数据
                currentPosition: state.position.inMilliseconds / 1000.0, // 转化为秒
                isPlaying: state.isPlaying,
                playbackSpeed: state.playbackSpeed,
              ),
            ),

            // 3. 底部进度条
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

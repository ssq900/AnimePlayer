import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../features/player/playback_controller.dart';
import '../models/rule.dart';

class PlayerPage extends ConsumerStatefulWidget {
  final String videoUrl;
  final String? episodeUrl;
  final String? title;          
  final String? animeTitle;     // ⚠️ 新增：兼容 detail_page 传入的 animeTitle
  final String? episodeTitle;
  final AnimeRule? rule;

  const PlayerPage({
    super.key, 
    required this.videoUrl, 
    this.episodeUrl,
    this.title,                 
    this.animeTitle,            // ⚠️ 新增
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
      final url = widget.videoUrl.isNotEmpty ? widget.videoUrl : (widget.episodeUrl ?? '');
      if (url.isNotEmpty) {
        ref.read(playbackControllerProvider.notifier).initialize(url);
      }
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
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(controller),
              ),
            ),
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

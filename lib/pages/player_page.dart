import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../features/player/playback_controller.dart';
import '../models/rule.dart';
import '../widgets/danmaku_overlay.dart';
import '../domain/danmaku_provider.dart'; // 🔥 引入数据模型和 Provider
import '../domain/danmaku_repository.dart'; // 🔥 引入聚合仓库

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
  List<DanmakuItem> _currentDanmakus = [];
  bool _isLoadingDanmaku = true;

  @override
  void initState() {
    super.initState();
    
    // 1. 初始化播放器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final url = (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) 
          ? widget.videoUrl! 
          : (widget.episodeUrl ?? '');
          
      if (url.isNotEmpty) {
        ref.read(playbackControllerProvider.notifier).initialize(url);
      }
    });

    // 2. 加载弹幕
    _loadDanmaku();
  }

  Future<void> _loadDanmaku() async {
    // 尝试从 widget 中获取真实的番剧名和集数
    final animeTitle = widget.animeTitle ?? widget.title ?? '未知番剧';
    
    // 简易提取集数（如果标题是 "第01集"，提取出 1）
    int episode = 1;
    if (widget.episodeTitle != null) {
      final match = RegExp(r'\d+').firstMatch(widget.episodeTitle!);
      if (match != null) {
        episode = int.tryParse(match.group(0)!) ?? 1;
      }
    }

    // 实例化仓库
    final repo = DanmakuRepository([
      LocalJsonProvider(), 
      DandanplayProvider()
    ]);
    
    try {
      // 并发拉取并合并
      final danmakus = await repo.loadAll(animeTitle, episode);
      
      if (mounted) {
        setState(() {
          // 如果真实数据为空（因为还没实现API），则使用测试数据兜底
          _currentDanmakus = danmakus.isNotEmpty ? danmakus : _generateMockData();
          _isLoadingDanmaku = false;
        });
      }
    } catch (e) {
      debugPrint('弹幕加载失败: $e');
      if (mounted) {
        setState(() {
          _currentDanmakus = _generateMockData(); // 报错也兜底
          _isLoadingDanmaku = false;
        });
      }
    }
  }

  // 兜底测试数据
  List<DanmakuItem> _generateMockData() {
    return List.generate(200, (index) {
      return DanmakuItem(
        time: index * 0.5,
        text: '测试弹幕 $index 号，Canvas 高性能渲染',
        color: index % 3 == 0 ? 0xFF0000 : 0xFFFFFF,
        type: index % 10 == 0 ? 1 : 0,
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
            
            // 2. 弹幕层（加入加载状态判断）
            Positioned.fill(
              child: _isLoadingDanmaku 
                ? const SizedBox() // 如果弹幕还在加载中，先不渲染弹幕层
                : DanmakuOverlay(
                    danmakus: _currentDanmakus, 
                    currentPosition: state.position.inMilliseconds / 1000.0, 
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

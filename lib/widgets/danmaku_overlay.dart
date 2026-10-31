import 'package:flutter/material.dart';

class DanmakuItem {
  final String text;
  final Duration time;
  final Color color;

  DanmakuItem({required this.text, required this.time, this.color = Colors.white});
}

class DanmakuOverlay extends StatefulWidget {
  final Duration currentPosition;
  final List<DanmakuItem> danmakus;
  final bool isPlaying;

  const DanmakuOverlay({
    super.key,
    required this.currentPosition,
    required this.danmakus,
    required this.isPlaying,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  // 简单实现：记录已经发射过的弹幕，防止重复发射
  final Set<String> _emittedIds = {};
  // 正在屏幕上飘的弹幕
  final List<DanmakuItem> _activeDanmakus = [];

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (!widget.isPlaying) return; // 暂停时不发射新弹幕

    // 进度重置（拖动进度条）时，清空屏幕
    if ((widget.currentPosition - oldWidget.currentPosition).abs() > const Duration(seconds: 2)) {
      _emittedIds.clear();
      _activeDanmakus.clear();
    }

    // 查找当前时间点应该出现的弹幕（允许 1 秒误差）
    for (var dm in widget.danmakus) {
      final dmId = '${dm.time.inMilliseconds}_${dm.text}';
      if (!_emittedIds.contains(dmId) &&
          widget.currentPosition >= dm.time &&
          widget.currentPosition < dm.time + const Duration(seconds: 1)) {
        _emittedIds.add(dmId);
        _activeDanmakus.add(dm);
        // 动画结束后移除
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted) {
            setState(() => _activeDanmakus.remove(dm));
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: _activeDanmakus.map((dm) {
          // 随机生成一个垂直轨道 (0 - 5)
          final track = dm.text.hashCode % 6;
          final top = 20.0 + (track * 30.0);
          
          return _AnimatedDanmaku(
            key: ValueKey(dm),
            text: dm.text,
            top: top,
            color: dm.color,
          );
        }).toList(),
      ),
    );
  }
}

class _AnimatedDanmaku extends StatefulWidget {
  final String text;
  final double top;
  final Color color;

  const _AnimatedDanmaku({super.key, required this.text, required this.top, required this.color});

  @override
  State<_AnimatedDanmaku> createState() => _AnimatedDanmakuState();
}

class _AnimatedDanmakuState extends State<_AnimatedDanmaku> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 8));
    _animation = Tween<double>(begin: 1.0, end: -1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Positioned(
          top: widget.top,
          // 从屏幕右侧进入，飘向左侧
          left: MediaQuery.of(context).size.width * _animation.value,
          child: child!,
        );
      },
      child: Text(
        widget.text,
        style: TextStyle(
          color: widget.color,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.black, blurRadius: 2, offset: Offset(1, 1))],
        ),
      ),
    );
  }
}

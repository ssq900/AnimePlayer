import 'dart:async';
import 'package:flutter/material.dart';

class DanmakuItem {
  final String text;
  final Duration time;
  final Color color;

  DanmakuItem({required this.text, required this.time, this.color = Colors.white});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DanmakuItem &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          time == other.time &&
          color == other.color;

  @override
  int get hashCode => text.hashCode ^ time.hashCode ^ color.hashCode;
}

class DanmakuOverlay extends StatefulWidget {
  final Duration currentPosition;
  final List<DanmakuItem> danmakus;
  final bool isPlaying;
  final List<String> blockWords; // 新增：屏蔽词列表
  final double opacity; // 新增：透明度

  const DanmakuOverlay({
    super.key,
    required this.currentPosition,
    required this.danmakus,
    required this.isPlaying,
    this.blockWords = const [],
    this.opacity = 1.0,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  final Set<DanmakuItem> _emittedItems = {};
  final List<DanmakuItem> _activeDanmakus = [];
  
  final List<DateTime> _trackReleaseTimes = List.generate(6, (_) => DateTime.now());

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isPlaying) return;

    if ((widget.currentPosition - oldWidget.currentPosition).abs() > const Duration(seconds: 2)) {
      _emittedItems.clear();
      _activeDanmakus.clear();
    }

    for (var dm in widget.danmakus) {
      if (!_emittedItems.contains(dm) && 
          widget.currentPosition >= dm.time && 
          widget.currentPosition < dm.time + const Duration(seconds: 1)) {
        
        // 核心修复：屏蔽词过滤
        bool isBlocked = false;
        for (var word in widget.blockWords) {
          if (word.isNotEmpty && dm.text.contains(word)) {
            isBlocked = true;
            break;
          }
        }
        if (isBlocked) {
           _emittedItems.add(dm); // 标记为已处理，避免反复拦截
           continue;
        }

        _emittedItems.add(dm);
        _activeDanmakus.add(dm);
        
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted) setState(() => _activeDanmakus.remove(dm));
        });
      }
    }
  }

  int _allocateTrack() {
    final now = DateTime.now();
    int bestTrack = 0;
    Duration minWait = const Duration(hours: 1);
    
    for (int i = 0; i < _trackReleaseTimes.length; i++) {
      final diff = _trackReleaseTimes[i].difference(now);
      if (diff.isNegative) return i;
      if (diff < minWait) {
        minWait = diff;
        bestTrack = i;
      }
    }
    return bestTrack;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: _activeDanmakus.map((dm) {
          final track = _allocateTrack();
          _trackReleaseTimes[track] = DateTime.now().add(const Duration(seconds: 3));
          final top = 20.0 + (track * 30.0);
          
          return _AnimatedDanmaku(
            key: ValueKey(dm), 
            text: dm.text, 
            top: top, 
            color: dm.color.withOpacity(widget.opacity),
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

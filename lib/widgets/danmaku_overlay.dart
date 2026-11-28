import 'package:flutter/material.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas; // 🔥 核心修复：使用别名防止类名冲突
import '../services/danmaku_provider.dart';

class DanmakuOverlay extends StatefulWidget {
  final List<DanmakuItem> danmakus;
  final double currentPosition;
  final bool isPlaying;
  final double playbackSpeed;

  const DanmakuOverlay({super.key, required this.danmakus, required this.currentPosition, required this.isPlaying, required this.playbackSpeed});

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  canvas.DanmakuController? _controller;
  int _lastPositionMs = 0;
  int _sentIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.danmakus.sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) { _controller?.resume(); } else { _controller?.pause(); }
    }

    final currentMs = (widget.currentPosition * 1000).toInt();
    final diff = (currentMs - _lastPositionMs).abs();
    
    if (diff > 2000) {
      _controller?.clear();
      _sentIndex = 0;
      while (_sentIndex < widget.danmakus.length && widget.danmakus[_sentIndex].time * 1000 < currentMs) {
        _sentIndex++;
      }
    } else {
      _dispatchDanmakus(currentMs);
    }
    _lastPositionMs = currentMs;
  }

  void _dispatchDanmakus(int currentMs) {
    if (_controller == null) return;
    while (_sentIndex < widget.danmakus.length && widget.danmakus[_sentIndex].time * 1000 <= currentMs + 500) {
      final item = widget.danmakus[_sentIndex];
      _controller!.addDanmaku(canvas.DanmakuContentItem(item.text, color: Color(item.color), type: _parseType(item.type)));
      _sentIndex++;
    }
  }

  canvas.DanmakuItemType _parseType(int type) {
    switch (type) {
      case 1: return canvas.DanmakuItemType.top;
      case 2: return canvas.DanmakuItemType.bottom;
      default: return canvas.DanmakuItemType.scroll;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: canvas.DanmakuScreen(
        createdController: (controller) {
          _controller = controller;
          _controller!.updateOption(_controller!.option.copyWith(
            area: 0.8, fontSize: 16, hideTop: false, hideBottom: false, hideScroll: false,
          ));
        },
        option: canvas.DanmakuOption(area: 0.8, fontSize: 16, duration: 8),
      ),
    );
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }
}

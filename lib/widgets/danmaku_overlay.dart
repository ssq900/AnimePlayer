import 'package:flutter/material.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';

// 统一的弹幕数据模型
class DanmakuItem {
  final double time; // 出现时间（秒）
  final String text;
  final int color;
  final int type; // 0:滚动, 1:顶部, 2:底部

  DanmakuItem({
    required this.time,
    required this.text,
    this.color = 0xFFFFFF,
    this.type = 0,
  });
}

class DanmakuOverlay extends StatefulWidget {
  final List<DanmakuItem> danmakus;
  final double currentPosition; // 当前播放进度（秒）
  final bool isPlaying;
  final double playbackSpeed;

  const DanmakuOverlay({
    super.key,
    required this.danmakus,
    required this.currentPosition,
    required this.isPlaying,
    required this.playbackSpeed,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  DanmakuController? _controller;
  int _lastPositionMs = 0;
  int _sentIndex = 0; // 记录已经发送到第几条弹幕

  @override
  void initState() {
    super.initState();
    // 初始化时将弹幕按时间排序
    widget.danmakus.sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 1. 同步播放/暂停状态
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller?.resume();
      } else {
        _controller?.pause();
      }
    }

    // 2. 同步倍速（实时调整 Canvas 渲染速度）
    if (widget.playbackSpeed != oldWidget.playbackSpeed) {
      _controller?.updateOption(_controller!.option.copyWith(speed: widget.playbackSpeed));
    }

    // 3. 同步进度（核心：处理拖动进度条/快进）
    final currentMs = (widget.currentPosition * 1000).toInt();
    final diff = (currentMs - _lastPositionMs).abs();
    
    // 如果进度跳跃超过 2 秒，说明用户拖动了进度条
    if (diff > 2000) {
      _controller?.clear();
      _sentIndex = 0;
      // 找到新进度下应该发送的弹幕索引
      while (_sentIndex < widget.danmakus.length && 
             widget.danmakus[_sentIndex].time * 1000 < currentMs) {
        _sentIndex++;
      }
    } else {
      // 正常播放，发送即将到达的弹幕
      _dispatchDanmakus(currentMs);
    }
    _lastPositionMs = currentMs;
  }

  void _dispatchDanmakus(int currentMs) {
    if (_controller == null) return;
    
    // 发送当前时间点前 0.5 秒内即将到达的弹幕
    while (_sentIndex < widget.danmakus.length && 
           widget.danmakus[_sentIndex].time * 1000 <= currentMs + 500) {
      final item = widget.danmakus[_sentIndex];
      
      _controller!.addDanmaku(
        DanmakuContentItem(
          item.text,
          color: Color(item.color),
          type: _parseType(item.type),
        ),
      );
      _sentIndex++;
    }
  }

  DanmakuItemType _parseType(int type) {
    switch (type) {
      case 1: return DanmakuItemType.top;
      case 2: return DanmakuItemType.bottom;
      default: return DanmakuItemType.scroll;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DanmakuScreen(
        createdController: (controller) {
          _controller = controller;
          // 初始化基础配置
          _controller!.updateOption(
            _controller!.option.copyWith(
              speed: widget.playbackSpeed,
              area: 0.8, // 弹幕占据屏幕上方 80%
              fontSize: 16,
              hideTop: false,
              hideBottom: false,
              hideScroll: false,
            ),
          );
        },
        option: DanmakuOption(
          area: 0.8,
          fontSize: 16,
          duration: 8, // 弹幕在屏幕上飘过的时间（秒）
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

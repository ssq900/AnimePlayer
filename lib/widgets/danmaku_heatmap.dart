import 'package:flutter/material.dart';
import 'danmaku_overlay.dart';

class DanmakuHeatmap extends StatelessWidget {
  final List<DanmakuItem> danmakus;
  final Duration totalDuration;
  final Duration currentPosition;

  const DanmakuHeatmap({
    super.key,
    required this.danmakus,
    required this.totalDuration,
    required this.currentPosition,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HeatmapPainter(
        danmakus: danmakus,
        totalDuration: totalDuration,
        currentPosition: currentPosition,
      ),
      child: const SizedBox(height: 24, width: double.infinity), // 高度控制热度条
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<DanmakuItem> danmakus;
  final Duration totalDuration;
  final Duration currentPosition;

  _HeatmapPainter({
    required this.danmakus,
    required this.totalDuration,
    required this.currentPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDuration.inSeconds == 0 || danmakus.isEmpty) return;

    final int totalSeconds = totalDuration.inSeconds;
    // 每 5 秒作为一个采样点
    final int pointCount = totalSeconds ~/ 5 + 1;
    final List<double> density = List.filled(pointCount, 0.0);

    // 1. 统计弹幕密度
    for (var dm in danmakus) {
      final index = dm.time.inSeconds ~/ 5;
      if (index >= 0 && index < pointCount) {
        density[index] += 1.0;
      }
    }

    // 2. 高斯平滑 (让波峰更平滑)
    final List<double> smoothDensity = List.filled(pointCount, 0.0);
    const double sigma = 2.0; // 平滑度
    for (int i = 0; i < pointCount; i++) {
      double sum = 0;
      for (int j = 0; j < pointCount; j++) {
        final diff = (i - j).toDouble();
        sum += density[j] * (1 / (sigma * 2.5)) * (1 / (1 + diff * diff));
      }
      smoothDensity[i] = sum;
    }

    // 找最大值用于归一化
    double maxDensity = 1.0;
    for (double d in smoothDensity) {
      if (d > maxDensity) maxDensity = d;
    }

    // 3. 绘制
    final paint = Paint()
      ..color = Colors.deepPurpleAccent.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, size.height);

    final double stepX = size.width / (pointCount - 1);
    for (int i = 0; i < pointCount; i++) {
      final x = i * stepX;
      final y = size.height - (smoothDensity[i] / maxDensity) * size.height;
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);

    // 4. 绘制当前播放进度指示线 (可选)
    final progressX = (currentPosition.inSeconds / totalSeconds) * size.width;
    final indicatorPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(progressX, 0), Offset(progressX, size.height), indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.currentPosition != currentPosition || oldDelegate.danmakus != danmakus;
  }
}

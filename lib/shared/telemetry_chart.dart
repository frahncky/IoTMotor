import 'package:flutter/material.dart';

class TelemetryChart extends StatelessWidget {
  final List<double> data;
  final double height;
  final Color color;

  const TelemetryChart({
    Key? key,
    required this.data,
    this.height = 120,
    this.color = Colors.blue,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _TelemetryChartPainter(data, color),
        child: Container(),
      ),
    );
  }
}

class _TelemetryChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _TelemetryChartPainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    final minY = data.reduce((a, b) => a < b ? a : b);
    final maxY = data.reduce((a, b) => a > b ? a : b);
    final scaleY = maxY - minY == 0 ? 1 : maxY - minY;
    for (int i = 0; i < data.length; i++) {
      final x = i * size.width / (data.length - 1);
      final y = size.height - ((data[i] - minY) / scaleY * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

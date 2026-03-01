import 'package:flutter/material.dart';

/// Transfer/swap style icon: two horizontal arrows pointing left and right.
class CompareIcon extends StatelessWidget {
  final double size;
  final Color color;

  const CompareIcon({super.key, this.size = 20, this.color = Colors.black87});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TransferIconPainter(color: color),
      ),
    );
  }
}

class _TransferIconPainter extends CustomPainter {
  final Color color;

  _TransferIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final cy = h / 2;
    final cx = w / 2;
    const pad = 3.0;
    const gap = 2.0;
    final halfLen = (w / 2 - pad - gap).clamp(4.0, 18.0);
    final leftTip = pad;
    final leftLineEnd = cx - gap;
    final rightLineStart = cx + gap;
    final rightTip = w - pad;

    // Left arrow: line from (leftLineEnd, cy) to (leftTip, cy), head at left
    canvas.drawLine(Offset(leftLineEnd, cy), Offset(leftTip + 5, cy), paint);
    _drawArrowHeadLeft(canvas, paint, leftTip + 5, cy);

    // Right arrow: line from (rightLineStart, cy) to (rightTip, cy), head at right
    canvas.drawLine(Offset(rightLineStart, cy), Offset(rightTip - 5, cy), paint);
    _drawArrowHeadRight(canvas, paint, rightTip - 5, cy);
  }

  void _drawArrowHeadLeft(Canvas canvas, Paint paint, double x, double y) {
    const s = 4.0;
    final path = Path()
      ..moveTo(x, y)
      ..lineTo(x + s, y - s)
      ..lineTo(x + s, y + s)
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
  }

  void _drawArrowHeadRight(Canvas canvas, Paint paint, double x, double y) {
    const s = 4.0;
    final path = Path()
      ..moveTo(x, y)
      ..lineTo(x - s, y - s)
      ..lineTo(x - s, y + s)
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

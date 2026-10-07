import 'package:flutter/material.dart';

/// Standard checkerboard pattern used to indicate transparency,
/// like Photoshop/GIMP. Used behind the processed (background-removed)
/// image so the user can clearly see which areas are actually transparent.
class CheckerboardBackground extends StatelessWidget {
  final Widget child;
  final double squareSize;

  const CheckerboardBackground({
    super.key,
    required this.child,
    this.squareSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerboardPainter(squareSize: squareSize),
      child: child,
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  final double squareSize;

  _CheckerboardPainter({required this.squareSize});

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = const Color(0xFFE0E0E0);
    final darkPaint = Paint()..color = const Color(0xFFBDBDBD);

    canvas.drawRect(Offset.zero & size, lightPaint);

    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final col = (x / squareSize).floor();
        final row = (y / squareSize).floor();
        final isDark = (col + row) % 2 == 0;
        if (isDark) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, squareSize, squareSize),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) =>
      oldDelegate.squareSize != squareSize;
}

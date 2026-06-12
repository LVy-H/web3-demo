import 'package:flutter/material.dart';

import 'theme.dart';

/// The Dark Bauhaus page texture: a 24px dot grid over the void, painted behind
/// [child] (mirrors the web `.dot-grid-bg` radial-gradient).
class DotGridBackground extends StatelessWidget {
  final Widget child;
  const DotGridBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DotGridPainter(), child: child);
}

class _DotGridPainter extends CustomPainter {
  static const _spacing = 24.0;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Db.void_);
    final dot = Paint()..color = const Color(0xFF232B3D);
    for (double y = _spacing / 2; y < size.height; y += _spacing) {
      for (double x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) => false;
}

import 'package:flutter/material.dart';

import 'qr_matrix.dart';

/// Renders a [QrMatrix] for [data] on a light tile with the standard 4-module
/// quiet zone, so any camera can lock onto it against the Dark Bauhaus void.
class QrView extends StatelessWidget {
  /// The payload to encode (deep link / ticket wire).
  final String data;

  /// Edge length of the rendered tile.
  final double dimension;

  const QrView({super.key, required this.data, this.dimension = 220});

  @override
  Widget build(BuildContext context) {
    final matrix = QrMatrix.encodeText(data);
    return Semantics(
      label: 'QR code',
      child: Container(
        width: dimension,
        height: dimension,
        color: Colors.white,
        child: CustomPaint(painter: _QrPainter(matrix)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  static const int _quietZone = 4;

  final QrMatrix matrix;

  _QrPainter(this.matrix);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF000000);
    final cells = matrix.size + 2 * _quietZone;
    final cell = size.shortestSide / cells;
    final offset = _quietZone * cell;
    for (var row = 0; row < matrix.size; row++) {
      for (var col = 0; col < matrix.size; col++) {
        if (!matrix.isDark(row, col)) continue;
        // Overlap each cell by a hairline so antialiasing can't open seams.
        canvas.drawRect(
          Rect.fromLTWH(
            offset + col * cell,
            offset + row * cell,
            cell + 0.5,
            cell + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) =>
      oldDelegate.matrix != matrix;
}

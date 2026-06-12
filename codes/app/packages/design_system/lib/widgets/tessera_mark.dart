/// The Tessera brand mark, painted from [Db] tokens — no SVG/asset
/// dependency. Mirrors `branding/tessera-mark.svg` exactly: a 3×3 mosaic of
/// square tiles with ONE segnale tile nudged out of the grid and rotated 8°
/// (the one anonymous voice). Geometry reference (512-unit space): 112 tile,
/// 24 gap, 64 margin; segnale tile translated (+10, −14), rotated about its
/// own center.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart';

class TesseraMark extends StatelessWidget {
  /// Edge length of the (square) mark.
  final double size;

  /// Paint the ink square behind the tiles. Off by default because the app
  /// already sits on [Db.void_]; turn on over any other surface.
  final bool background;

  const TesseraMark({super.key, this.size = 48, this.background = false});

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Tessera',
    child: CustomPaint(
      size: Size.square(size),
      painter: _TesseraMarkPainter(background: background),
    ),
  );
}

class _TesseraMarkPainter extends CustomPainter {
  final bool background;

  const _TesseraMarkPainter({required this.background});

  // 512-space constants, identical to branding/tessera-mark.svg.
  static const double _space = 512;
  static const double _tile = 112;
  static const double _step = 136; // tile + gap
  static const double _margin = 64;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / _space;
    final paint = Paint()..style = PaintingStyle.fill;

    if (background) {
      paint.color = Db.void_;
      canvas.drawRect(Offset.zero & size, paint);
    }

    // Eight grid tiles; (row 0, col 2) is skipped — that slot belongs to the
    // segnale tile below. Mute tiles at (1,1) and (2,0) give mosaic texture.
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        if (row == 0 && col == 2) continue;
        final isMute = (row == 1 && col == 1) || (row == 2 && col == 0);
        paint.color = isMute ? Db.mute : Db.chalk;
        canvas.drawRect(
          Rect.fromLTWH(
            (_margin + col * _step) * s,
            (_margin + row * _step) * s,
            _tile * s,
            _tile * s,
          ),
          paint,
        );
      }
    }

    // The one segnale tile: grid slot (0,2) translated (+10, −14), rotated 8°
    // about its own center (402, 106 in 512-space).
    paint.color = Db.segnale;
    canvas
      ..save()
      ..translate(402 * s, 106 * s)
      ..rotate(8 * math.pi / 180)
      ..drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: _tile * s,
          height: _tile * s,
        ),
        paint,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_TesseraMarkPainter oldDelegate) =>
      oldDelegate.background != background;
}

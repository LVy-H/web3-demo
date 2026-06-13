// Permanent headless WCAG-AA contrast guard for the Dark Bauhaus dim-text
// tokens. The dim meta-text tokens ({chalkDim, mute, muteDim}) are rendered on
// the page background AND on the card surfaces (slate / slate2 / slate3) — small
// (<= 18px) mono meta text such as receipt date/code and the blind "sealed"
// note. WCAG 2.x AA requires >= 4.5:1 contrast for normal-size text.
//
// This test computes the contrast ratio from the WCAG relative-luminance
// formula and asserts every (dim-text-token, surface) pair clears 4.5:1. Colour
// values are read directly off the `Db` class (never hardcoded here) so this
// guard tracks the real tokens: any future regression that dims these below AA
// fails the suite.
import 'dart:math' as math;

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Linearise a single 0..255 sRGB channel per the WCAG definition.
double _linearize(int channel8Bit) {
  final c = channel8Bit / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG relative luminance: L = 0.2126·R + 0.7152·G + 0.0722·B over the
/// linearised channels of [color].
double _relativeLuminance(Color color) {
  final argb = color.toARGB32();
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 0.2126 * _linearize(r) +
      0.7152 * _linearize(g) +
      0.0722 * _linearize(b);
}

/// WCAG contrast ratio: (L_light + 0.05) / (L_dark + 0.05), always >= 1.0.
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  // The surfaces these dim tokens are actually painted on: the page background
  // plus every card surface in the catalogue / detail flows.
  const surfaces = <String, Color>{
    'void_': Db.void_,
    'slate': Db.slate,
    'slate2': Db.slate2,
    'slate3': Db.slate3,
  };

  // The dim meta-text tokens used for real (small) text on those surfaces.
  const dimTextTokens = <String, Color>{
    'chalkDim': Db.chalkDim,
    'mute': Db.mute,
    'muteDim': Db.muteDim,
  };

  const aaNormalText = 4.5; // WCAG 2.x AA, text <= 18px.

  group('WCAG-AA contrast: dim text tokens on every surface they render on', () {
    for (final token in dimTextTokens.entries) {
      for (final surface in surfaces.entries) {
        test('${token.key} on ${surface.key} >= $aaNormalText:1', () {
          final ratio = _contrastRatio(token.value, surface.value);
          expect(
            ratio,
            greaterThanOrEqualTo(aaNormalText),
            reason:
                '${token.key} (#${token.value.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}) '
                'on ${surface.key} '
                '(#${surface.value.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}) '
                'is ${ratio.toStringAsFixed(2)}:1 — fails WCAG AA (4.5:1) for normal-size text.',
          );
        });
      }
    }
  });

  // Guard the visual hierarchy: lifting the dim tokens for legibility must not
  // reorder them. chalk > chalkDim > mute > muteDim by relative luminance, with
  // muteDim staying the dimmest legible tier.
  test(
    'relative-luminance hierarchy is preserved (chalk > chalkDim > mute > muteDim)',
    () {
      final chalk = _relativeLuminance(Db.chalk);
      final chalkDim = _relativeLuminance(Db.chalkDim);
      final mute = _relativeLuminance(Db.mute);
      final muteDim = _relativeLuminance(Db.muteDim);

      expect(
        chalk,
        greaterThan(chalkDim),
        reason: 'chalk must be brighter than chalkDim',
      );
      expect(
        chalkDim,
        greaterThan(mute),
        reason: 'chalkDim must be brighter than mute',
      );
      expect(
        mute,
        greaterThan(muteDim),
        reason: 'mute must be brighter than muteDim (muteDim stays dimmest)',
      );
    },
  );
}

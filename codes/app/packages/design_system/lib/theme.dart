import 'package:flutter/material.dart';

/// Re-exported so the responsive content-width helper is part of the
/// design_system public surface that consumers already pull in via `theme.dart`.
export 'responsive.dart';

/// Dark Bauhaus design tokens — ported from the web app's `index.css`
/// (`--color-db-*`). Sharp geometry, hairline rules, signal-red accents,
/// Inter + JetBrains Mono. Source of truth so web and Flutter match.
abstract class Db {
  static const void_ = Color(0xFF0A0C10); // page background
  static const slate = Color(0xFF1A1F2E); // active card surface
  static const slate2 = Color(0xFF1F2436); // upcoming card
  static const slateDim = Color(0xFF171B27); // ended card
  static const slate3 = Color(0xFF11141F); // filter strip / panels
  static const slate4 = Color(0xFF141826); // ended chip fill
  static const chalk = Color(0xFFF5F7FA); // primary text
  static const chalkDim = Color(0xFFC9D0DB); // secondary text
  static const mute = Color(0xFF868FA3); // mono labels / meta
  static const muteDim = Color(
    0xFF828C9E,
  ); // tertiary — dimmest legible (>= WCAG AA 4.5:1 on void_ AND all card surfaces slate/slate2/slate3)
  static const rule = Color(0xFF2A3140); // hairline border
  static const ruleSoft = Color(0xFF1F2433); // inner divider
  static const segnale = Color(0xFFFF3B5C); // primary signal (active/CTA)
  static const segnaleD = Color(0xFFCC2E49); // darker signal
  static const oltremare = Color(0xFF4D7CFF); // secondary (upcoming)
  static const success = Color(0xFF10FF8A); // success / passed
  static const amber = Color(0xFFF59E0B); // 4th option

  // Per-category hues (muted).
  static const catGovernance = Color(0xFF5A8F7B);
  static const catTreasury = Color(0xFF8A7359);
  static const catTech = Color(0xFF6A7592);
  static const catSocial = Color(0xFF946B87);

  static const fontSans = 'Inter';
  static const fontMono = 'JetBrainsMono';

  // ── option palette (cycles 0..3), mirrors lib/pollOptionPalette.ts ──
  static const _optionColors = [success, segnale, oltremare, amber];
  static Color optionColor(int i) => _optionColors[((i % 4) + 4) % 4];

  // ── categories ──
  static const categoryLabels = ['Governance', 'Treasury', 'Tech', 'Social'];
  static const _categoryColors = [
    catGovernance,
    catTreasury,
    catTech,
    catSocial,
  ];
  static Color categoryColor(int i) => _categoryColors[((i % 4) + 4) % 4];

  /// Derive a stable category index from a poll address (last hex digit mod 4),
  /// matching the web client's `deriveCategory`.
  static int categoryFor(String pollAddress) {
    if (pollAddress.isEmpty) return 2; // tech
    final n = int.tryParse(
      pollAddress.substring(pollAddress.length - 1),
      radix: 16,
    );
    return n == null ? 2 : n % 4;
  }
}

/// Variable-weight Inter text. `wght` drives the font's `wght` axis directly so
/// extrabold actually renders extrabold (a single variable TTF is bundled).
TextStyle dbSans(
  double size,
  int wght,
  Color color, {
  double? height,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: Db.fontSans,
  fontSize: size,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontWeight: FontWeight.values[(wght ~/ 100 - 1).clamp(0, 8)],
  fontVariations: [FontVariation('wght', wght.toDouble())],
);

/// Variable-weight JetBrains Mono text.
TextStyle dbMono(
  double size,
  Color color, {
  int wght = 400,
  double? letterSpacing,
  double? height,
}) => TextStyle(
  fontFamily: Db.fontMono,
  fontSize: size,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontWeight: FontWeight.values[(wght ~/ 100 - 1).clamp(0, 8)],
  fontVariations: [FontVariation('wght', wght.toDouble())],
);

/// Wide-tracked uppercase mono label (the "stamped" Bauhaus label).
TextStyle dbLabel({
  double size = 10,
  Color color = Db.mute,
  double tracking = 0.18,
  int wght = 500,
}) => dbMono(size, color, wght: wght, letterSpacing: size * tracking);

/// Big extrabold hero display (caller passes a clamped size).
TextStyle dbHero(double size) =>
    dbSans(size, 800, Db.chalk, height: 0.94, letterSpacing: size * -0.035);

/// Section heading ("CAST YOUR VOTE", "LIVE RESULTS").
TextStyle get dbSectionTitle =>
    dbSans(16, 800, Db.chalk, letterSpacing: 16 * 0.05);

/// The Dark Bauhaus [ThemeData] — Inter default, void scaffold, sharp shapes.
ThemeData buildDarkBauhausTheme() {
  const scheme = ColorScheme.dark(
    surface: Db.slate,
    onSurface: Db.chalk,
    primary: Db.segnale,
    onPrimary: Db.chalk,
    secondary: Db.oltremare,
    onSecondary: Db.void_,
    error: Db.segnale,
    tertiary: Db.success,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: Db.fontSans,
    scaffoldBackgroundColor: Db.void_,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Db.void_,
      foregroundColor: Db.chalk,
      elevation: 0,
      centerTitle: false,
    ),
    dividerColor: Db.rule,
    textTheme: base.textTheme.apply(
      bodyColor: Db.chalk,
      displayColor: Db.chalk,
    ),
  );
}

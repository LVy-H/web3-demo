import 'package:flutter/material.dart';

/// Immutable value object naming every colour role the app themes. A theme is
/// exactly one [DbPalette]; [Db] resolves its colour accessors against the
/// currently-active palette. Each curated theme is a `const DbPalette(...)`, so
/// the palettes themselves stay compile-time constant — only the live
/// [Db._current] pointer is mutable.
@immutable
class DbPalette {
  // surfaces
  final Color void_, slate, slate2, slateDim, slate3, slate4;
  // text
  final Color chalk, chalkDim, mute, muteDim;
  // borders
  final Color rule, ruleSoft;
  // signals
  final Color segnale, segnaleD, oltremare, success, amber;
  // category hues
  final Color catGovernance, catTreasury, catTech, catSocial;
  // drives ThemeData light/dark
  final Brightness brightness;

  const DbPalette({
    required this.void_,
    required this.slate,
    required this.slate2,
    required this.slateDim,
    required this.slate3,
    required this.slate4,
    required this.chalk,
    required this.chalkDim,
    required this.mute,
    required this.muteDim,
    required this.rule,
    required this.ruleSoft,
    required this.segnale,
    required this.segnaleD,
    required this.oltremare,
    required this.success,
    required this.amber,
    required this.catGovernance,
    required this.catTreasury,
    required this.catTech,
    required this.catSocial,
    required this.brightness,
  });
}

/// Dark Bauhaus palette — the current/default theme, ported from the web app's
/// `index.css` (`--color-db-*`). Sharp geometry, hairline rules, signal-red
/// accents. The colour values are the verbatim historical [Db] constants.
const darkBauhausPalette = DbPalette(
  void_: Color(0xFF0A0C10), // page background
  slate: Color(0xFF1A1F2E), // active card surface
  slate2: Color(0xFF1F2436), // upcoming card
  slateDim: Color(0xFF171B27), // ended card
  slate3: Color(0xFF11141F), // filter strip / panels
  slate4: Color(0xFF141826), // ended chip fill
  chalk: Color(0xFFF5F7FA), // primary text
  chalkDim: Color(0xFFC9D0DB), // secondary text
  mute: Color(0xFF7A8599), // mono labels / meta
  muteDim: Color(0xFF4D5566), // tertiary
  rule: Color(0xFF2A3140), // hairline border
  ruleSoft: Color(0xFF1F2433), // inner divider
  segnale: Color(0xFFFF3B5C), // primary signal (active/CTA)
  segnaleD: Color(0xFFCC2E49), // darker signal
  oltremare: Color(0xFF4D7CFF), // secondary (upcoming)
  success: Color(0xFF10FF8A), // success / passed
  amber: Color(0xFFF59E0B), // 4th option
  catGovernance: Color(0xFF5A8F7B),
  catTreasury: Color(0xFF8A7359),
  catTech: Color(0xFF6A7592),
  catSocial: Color(0xFF946B87),
  brightness: Brightness.dark,
);

/// Dark Bauhaus design tokens — colour roles resolve at runtime against the
/// active [DbPalette] ([_current]), so the app's palette can be swapped without
/// touching call sites. Defaults to [darkBauhausPalette] so `Db.*` is never null
/// even before any startup code runs. Source of truth so web and Flutter match.
abstract class Db {
  /// The live palette. Initialised to the Dark Bauhaus default (so every read is
  /// valid from the first frame). M2's theme controller swaps it via [palette].
  static DbPalette _current = darkBauhausPalette;

  /// Seam for the M2 theme controller: swap the active palette app-wide. (No
  /// controller/persistence here — M1 is the behaviour-preserving refactor only.)
  static set palette(DbPalette p) => _current = p;

  /// The active palette (read-only access for theme builders).
  static DbPalette get activePalette => _current;

  static Color get void_ => _current.void_; // page background
  static Color get slate => _current.slate; // active card surface
  static Color get slate2 => _current.slate2; // upcoming card
  static Color get slateDim => _current.slateDim; // ended card
  static Color get slate3 => _current.slate3; // filter strip / panels
  static Color get slate4 => _current.slate4; // ended chip fill
  static Color get chalk => _current.chalk; // primary text
  static Color get chalkDim => _current.chalkDim; // secondary text
  static Color get mute => _current.mute; // mono labels / meta
  static Color get muteDim => _current.muteDim; // tertiary
  static Color get rule => _current.rule; // hairline border
  static Color get ruleSoft => _current.ruleSoft; // inner divider
  static Color get segnale => _current.segnale; // primary signal (active/CTA)
  static Color get segnaleD => _current.segnaleD; // darker signal
  static Color get oltremare => _current.oltremare; // secondary (upcoming)
  static Color get success => _current.success; // success / passed
  static Color get amber => _current.amber; // 4th option

  // Per-category hues (muted).
  static Color get catGovernance => _current.catGovernance;
  static Color get catTreasury => _current.catTreasury;
  static Color get catTech => _current.catTech;
  static Color get catSocial => _current.catSocial;

  // Fonts and category metadata are not themed in v1 — stay const.
  static const fontSans = 'Inter';
  static const fontMono = 'JetBrainsMono';

  // ── option palette (cycles 0..3), mirrors lib/pollOptionPalette.ts ──
  static Color optionColor(int i) {
    final j = ((i % 4) + 4) % 4;
    switch (j) {
      case 0:
        return success;
      case 1:
        return segnale;
      case 2:
        return oltremare;
      default:
        return amber;
    }
  }

  // ── categories ──
  static const categoryLabels = ['Governance', 'Treasury', 'Tech', 'Social'];
  static Color categoryColor(int i) {
    final j = ((i % 4) + 4) % 4;
    switch (j) {
      case 0:
        return catGovernance;
      case 1:
        return catTreasury;
      case 2:
        return catTech;
      default:
        return catSocial;
    }
  }

  /// Derive a stable category index from a poll address (last hex digit mod 4),
  /// matching the web client's `deriveCategory`.
  static int categoryFor(String pollAddress) {
    if (pollAddress.isEmpty) return 2; // tech
    final n = int.tryParse(pollAddress.substring(pollAddress.length - 1), radix: 16);
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
}) =>
    TextStyle(
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
}) =>
    TextStyle(
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
  Color? color,
  double tracking = 0.18,
  int wght = 500,
}) =>
    dbMono(size, color ?? Db.mute, wght: wght, letterSpacing: size * tracking);

/// Big extrabold hero display (caller passes a clamped size).
TextStyle dbHero(double size) =>
    dbSans(size, 800, Db.chalk, height: 0.94, letterSpacing: size * -0.035);

/// Section heading ("CAST YOUR VOTE", "LIVE RESULTS").
TextStyle get dbSectionTitle =>
    dbSans(16, 800, Db.chalk, letterSpacing: 16 * 0.05);

/// Build a [ThemeData] from a [DbPalette]. Light/dark is driven by
/// `p.brightness`; the default ([darkBauhausPalette]) is visually identical to
/// the historical Dark Bauhaus theme.
ThemeData buildTheme(DbPalette p) {
  final scheme = p.brightness == Brightness.dark
      ? ColorScheme.dark(
          surface: p.slate,
          onSurface: p.chalk,
          primary: p.segnale,
          onPrimary: p.chalk,
          secondary: p.oltremare,
          onSecondary: p.void_,
          error: p.segnale,
          tertiary: p.success,
        )
      : ColorScheme.light(
          surface: p.slate,
          onSurface: p.chalk,
          primary: p.segnale,
          onPrimary: p.chalk,
          secondary: p.oltremare,
          onSecondary: p.void_,
          error: p.segnale,
          tertiary: p.success,
        );

  final base = ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    fontFamily: Db.fontSans,
    scaffoldBackgroundColor: p.void_,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.void_,
      foregroundColor: p.chalk,
      elevation: 0,
      centerTitle: false,
    ),
    dividerColor: p.rule,
    textTheme: base.textTheme.apply(bodyColor: p.chalk, displayColor: p.chalk),
  );
}

/// The Dark Bauhaus [ThemeData] — Inter default, void scaffold, sharp shapes.
/// Thin wrapper over [buildTheme] for the historical caller.
ThemeData buildDarkBauhausTheme() => buildTheme(darkBauhausPalette);

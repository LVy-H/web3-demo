import 'package:flutter/material.dart';

/// Dark Bauhaus design tokens — ported from the web app's `index.css`
/// (`--color-db-*`, the default dark theme). Source of truth for the Flutter
/// look so web and mobile stay visually consistent.
abstract class Db {
  static const void_ = Color(0xFF0A0C10); // page background
  static const slate = Color(0xFF1A1F2E); // active card surface
  static const slate2 = Color(0xFF1F2436); // upcoming card
  static const slateDim = Color(0xFF171B27); // ended card
  static const slate3 = Color(0xFF11141F); // filter strip bg
  static const chalk = Color(0xFFF5F7FA); // primary text
  static const chalkDim = Color(0xFFC9D0DB); // secondary text
  static const mute = Color(0xFF7A8599); // mono labels / meta
  static const rule = Color(0xFF2A3140); // hairline rule
  static const ruleSoft = Color(0xFF1F2433); // inner divider
  static const segnale = Color(0xFFFF3B5C); // primary signal (active)
  static const segnaleD = Color(0xFFCC2E49); // darker signal
  static const oltremare = Color(0xFF4D7CFF); // secondary (upcoming)
  static const success = Color(0xFF10FF8A); // success / passed

  static const fontSans = 'Inter';
  static const fontMono = 'JetBrainsMono';
}

/// The Dark Bauhaus [ThemeData]. Fonts fall back to platform defaults until the
/// Inter / JetBrains Mono families are bundled (Risk-B-adjacent polish).
ThemeData buildDarkBauhausTheme() {
  const scheme = ColorScheme.dark(
    surface: Db.slate,
    onSurface: Db.chalk,
    primary: Db.segnale,
    onPrimary: Db.chalk,
    secondary: Db.oltremare,
    onSecondary: Db.chalk,
    error: Db.segnale,
    tertiary: Db.success,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Db.void_,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Db.void_,
      foregroundColor: Db.chalk,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: Db.slate,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Db.rule),
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    dividerColor: Db.rule,
    textTheme: base.textTheme.apply(
      bodyColor: Db.chalk,
      displayColor: Db.chalk,
    ),
  );
}

/// Monospace label style (JetBrains Mono look) for addresses, codes, meta.
const TextStyle dbMonoLabel = TextStyle(
  fontFamily: Db.fontMono,
  fontSize: 11,
  letterSpacing: 1.6,
  color: Db.mute,
);

import 'package:flutter/material.dart';

import '../game/skins.dart';

/// The app's colours. Dark velvet by default, with a light variant.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.dark,
    required this.bg,
    required this.bgGlow,
    required this.card,
    required this.cardHi,
    required this.line,
    required this.ink,
    required this.dim,
    required this.brass,
    required this.brassDeep,
    required this.brassInk,
    required this.good,
    required this.danger,
    required this.shadow,
  });

  final bool dark;
  final Color bg;

  /// Centre of the bench spotlight.
  final Color bgGlow;
  final Color card;
  final Color cardHi;
  final Color line;
  final Color ink;
  final Color dim;
  final Color brass;

  /// Underside of brass buttons.
  final Color brassDeep;
  final Color brassInk;
  final Color good;
  final Color danger;
  final Color shadow;

  static const night = AppPalette(
    dark: true,
    bg: Color(0xFF18121F),
    bgGlow: Color(0xFF2E2240),
    card: Color(0xFF241B30),
    cardHi: Color(0xFF2F2440),
    line: Color(0xFF3D304D),
    ink: Color(0xFFF4EEE2),
    dim: Color(0xFFA99FB6),
    brass: Color(0xFFE0AD4A),
    brassDeep: Color(0xFF9B7424),
    brassInk: Color(0xFF1C1405),
    good: Color(0xFF5ED6A0),
    danger: Color(0xFFF0705F),
    shadow: Color(0xFF07040A),
  );

  static const day = AppPalette(
    dark: false,
    bg: Color(0xFFE9E4F0),
    bgGlow: Color(0xFFFBF9FD),
    card: Color(0xFFFFFFFF),
    cardHi: Color(0xFFF4F0F8),
    line: Color(0xFFD5CCE0),
    ink: Color(0xFF241B30),
    dim: Color(0xFF6C6280),
    brass: Color(0xFFD9A136),
    brassDeep: Color(0xFF9B7424),
    brassInk: Color(0xFF1C1405),
    good: Color(0xFF1F9D68),
    danger: Color(0xFFD14B3A),
    shadow: Color(0xFF3A2E49),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? night;

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(AppPalette? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

const String kDisplayFont = 'Unbounded';
const String kBodyFont = 'Figtree';

ThemeData buildTheme(AppPalette p) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: p.bg,
    fontFamily: kBodyFont,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: p.brass,
          brightness: p.dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: p.brass,
          onPrimary: p.brassInk,
          surface: p.bg,
          onSurface: p.ink,
        ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: [p],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
  );
}

/// Text styles used across the app.
class AppText {
  static TextStyle display(
    AppPalette p,
    double size, {
    FontWeight weight = FontWeight.w700,
  }) => TextStyle(
    fontFamily: kDisplayFont,
    fontSize: size,
    fontWeight: weight,
    color: p.ink,
    height: 1.1,
    letterSpacing: -0.02 * size,
  );

  static TextStyle body(
    AppPalette p,
    double size, {
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) => TextStyle(
    fontFamily: kBodyFont,
    fontSize: size,
    fontWeight: weight,
    color: color ?? p.ink,
    height: 1.3,
  );

  static TextStyle label(AppPalette p, {Color? color}) => TextStyle(
    fontFamily: kBodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: color ?? p.dim,
    letterSpacing: 1.1,
    height: 1.2,
  );
}

/// A skin's colours as Flutter colours, with the shades the renderer needs.
class RingSkin {
  RingSkin(this.def) : colors = [for (final c in def.colors) Color(c)];

  final SkinDef def;
  final List<Color> colors;

  Color color(int index) => colors[index % colors.length];

  static final Map<String, RingSkin> _cache = {};
  static RingSkin of(String id) => _cache[id] ??= RingSkin(skinById(id));
}

Color shade(Color c, double light) {
  // light 0 = deep shadow, 1 = fully lit.
  final k = 0.42 + 0.58 * light;
  return Color.fromARGB(
    255,
    (c.r * 255 * k).round().clamp(0, 255),
    (c.g * 255 * k).round().clamp(0, 255),
    (c.b * 255 * k).round().clamp(0, 255),
  );
}

Color tint(Color c, double amount) => Color.lerp(c, Colors.white, amount)!;

import 'package:flutter/material.dart';

/// The Swarm lives in one committed visual world: a deep-sea instrument screen.
/// There is no light theme on purpose — the whole product is darkness you
/// have to earn light in.
class Swarm {
  // ground
  static const abyss = Color(0xFF04060B);
  static const trench = Color(0xFF090E16);
  static const silt = Color(0xFF0F1723);
  static const ridge = Color(0xFF182231);
  static const line = Color(0x248CAFCD);

  // ink
  static const foam = Color(0xFFE4EFF4);
  static const fog = Color(0xFF8298AE);
  static const murk = Color(0xFF4E6178);

  // signal
  static const plankton = Color(0xFF6FF3CE);
  static const bard = Color(0xFFFFC46B);
  static const rogue = Color(0xFFFF4D6D);
  static const mage = Color(0xFF8E7CFF);

  // proximity bands — semantic, never decorative
  static const cold = Color(0xFF4C86FF);
  static const warm = Color(0xFFFFC46B);
  static const hot = Color(0xFFFF7A45);
  static const critical = Color(0xFFFF3B5C);

  // All three families are bundled variable fonts, so the app renders
  // identically on a cold start with no signal — which is the only kind of
  // start an emergence night ever gets.

  /// Machine chrome. Every number, label and readout.
  static TextStyle data({
    double size = 9.5,
    Color color = fog,
    FontWeight weight = FontWeight.w500,
    double tracking = 1.4,
  }) =>
      TextStyle(
        fontFamily: 'JetBrainsMono',
        fontVariations: [FontVariation('wght', _axis(weight))],
        fontWeight: weight,
        fontSize: size,
        color: color,
        letterSpacing: tracking,
        height: 1.3,
      );

  /// Human voices. Whispers, blurbs, anything a person actually said.
  /// Newsreader carries an optical-size axis, so it is tuned to the point size
  /// rather than scaled — small text stays sturdy, large text stays elegant.
  static TextStyle voice({
    double size = 13,
    Color color = foam,
    FontWeight weight = FontWeight.w300,
    bool italic = false,
  }) =>
      TextStyle(
        fontFamily: 'Newsreader',
        fontVariations: [
          FontVariation('wght', _axis(weight)),
          FontVariation('opsz', size.clamp(6.0, 72.0)),
        ],
        fontWeight: weight,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontSize: size,
        color: color,
        height: 1.45,
      );

  /// Structure. Headings and the wordmark.
  static TextStyle display({
    double size = 18,
    Color color = foam,
    FontWeight weight = FontWeight.w800,
    double tracking = -0.3,
  }) =>
      TextStyle(
        fontFamily: 'Syne',
        fontVariations: [FontVariation('wght', _axis(weight))],
        fontWeight: weight,
        fontSize: size,
        color: color,
        letterSpacing: tracking,
        height: 1.1,
      );

  static double _axis(FontWeight w) => w.value.toDouble();

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: abyss,
        colorScheme: const ColorScheme.dark(
          surface: trench,
          primary: plankton,
          onPrimary: abyss,
          secondary: mage,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      );
}

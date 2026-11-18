import 'package:flutter/material.dart';

class CyberTheme {
  CyberTheme._();

  static const Color bgVoid = Color(0xFF070A0F);
  static const Color bgSurface = Color(0xFF101520);
  static const Color bgSurfaceElevated = Color(0xFF161D2C);
  static const Color borderHairline = Color(0x18FFFFFF);

  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color emeraldOk = Color(0xFF10B981);
  static const Color amberWait = Color(0xFFF59E0B);
  static const Color crimsonOff = Color(0xFFEF4444);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static ThemeData buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgVoid,
      colorScheme: const ColorScheme.dark(
        primary: cyanAccent,
        secondary: emeraldOk,
        surface: bgSurface,
        error: crimsonOff,
      ),
      cardTheme: CardThemeData(
        color: bgSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderHairline, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgVoid,
        elevation: 0,
        centerTitle: false,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: cyanAccent,
        inactiveTrackColor: Colors.white.withAlpha(31),
        thumbColor: cyanAccent,
        overlayColor: cyanAccent.withAlpha(41),
      ),
      useMaterial3: true,
    );
  }
}

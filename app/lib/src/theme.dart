import 'package:flutter/material.dart';

/// Pro-audio dark palette, no stock Material surfaces.
abstract final class AppColors {
  static const bg = Color(0xFF0B0E13);
  static const panel = Color(0xFF11151D);
  static const panelBorder = Color(0xFF222A38);
  static const grid = Color(0xFF1A2130);
  static const text = Color(0xFFE4E9F2);
  static const dim = Color(0xFF7E8798);
  static const accent = Color(0xFF4FD1E0); // cyan: live / "now"
  static const accent2 = Color(0xFF8A7BFF); // violet: session
  static const ok = Color(0xFF4CC38A);
  static const warn = Color(0xFFE5484D);
  static const amber = Color(0xFFE8B44F);
}

abstract final class AppText {
  static const mono = TextStyle(
    fontFamily: 'Menlo',
    fontSize: 11,
    color: AppColors.dim,
    letterSpacing: 0.2,
  );
  static const monoBright = TextStyle(
    fontFamily: 'Menlo',
    fontSize: 11,
    color: AppColors.text,
    letterSpacing: 0.2,
  );
  static const label = TextStyle(
    fontSize: 11,
    color: AppColors.dim,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w600,
  );
  static const title = TextStyle(
    fontSize: 13,
    color: AppColors.text,
    letterSpacing: 2.5,
    fontWeight: FontWeight.w700,
  );
}

ThemeData buildTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.panel,
    fontFamily: '.AppleSystemUIFont',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent2,
      surface: AppColors.panel,
      error: AppColors.warn,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AppColors.panelBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      labelStyle: const TextStyle(color: AppColors.dim, fontSize: 12),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(fontSize: 13, color: AppColors.text),
    ),
  );
}

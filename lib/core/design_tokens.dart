import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0F172A);
  static const surface = Color(0xFF141C32);
  static const surfaceHigh = Color(0xFF1C2540);
  static const primary = Color(0xFF7C3AED);
  static const secondary = Color(0xFF6366F1);
  static const accent = Color(0xFF0891B2);
  static const text = Color(0xFFF8FAFC);
  static const textMuted = Color(0xFFCBD5E1);
  static const line = Color(0x2EFFFFFF);
  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF10B981);
}

class AppSpacing {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
}

class DanxeTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      tertiary: AppColors.accent,
      error: AppColors.danger,
      surface: AppColors.surface,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
        fontFamily: 'Roboto',
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: TextStyle(color: AppColors.text),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.line,
        thumbColor: AppColors.text,
        overlayColor: AppColors.accent.withOpacity(0.14),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.text,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.line),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}


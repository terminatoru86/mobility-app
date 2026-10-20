import 'package:flutter/material.dart';

/// MOBIlity colors. Green / yellow / red / grey mean status only.
class AppColors {
  static const ink = Color(0xFF13212B);
  static const primary = Color(0xFF24333C);
  static const soft = Color(0xFF55666F);
  static const paper = Color(0xFFF1F4F5);
  static const line = Color(0xFFD6DEE2);
  static const blue = Color(0xFF2F6FDC);

  static const green = Color(0xFF5D9A30);
  static const greenTint = Color(0xFFE3F0D8);
  static const greenDark = Color(0xFF2E6416);
  static const yellow = Color(0xFFE9A800);
  static const yellowTint = Color(0xFFFFF1C9);
  static const yellowDark = Color(0xFF6E4E00);
  static const red = Color(0xFFE0484D);
  static const redTint = Color(0xFFFDE1E2);
  static const redDark = Color(0xFF9E2328);
  static const grey = Color(0xFF97A3A9);
  static const greyTint = Color(0xFFEEF1F2);
  static const greyDark = Color(0xFF55666F);
  static const slate = Color(0xFF566874);
  static const slateTint = Color(0xFFEAEFF2);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light),
    scaffoldBackgroundColor: const Color(0xFFF3F5F6),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

/// Colour tokens from the Kairo plan. Use these instead of literal colours.
abstract final class KairoColors {
  static const background = Color(0xFF11101C);
  static const surface = Color(0xFF1C1A2B);
  static const surfaceRaised = Color(0xFF26233A);
  static const navBar = Color(0xFF161523);
  static const outline = Color(0xFF3A3654);
  static const primary = Color(0xFF8B5CF6);
  static const primarySoft = Color(0xFFA78BFA);
  static const accent = Color(0xFFFF6B8A);
  static const info = Color(0xFF38BDF8);
  static const success = Color(0xFF4ADE80);
  static const star = Color(0xFFFBBF24);
  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB8B5C9);
  static const textMuted = Color(0xFF8E8AA6);
}

abstract final class KairoSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;

  /// Horizontal page gutter used by every screen.
  static const gutter = 20.0;
}

abstract final class KairoRadii {
  static const card = 12.0;
  static const panel = 14.0;
  static const hero = 20.0;
  static const pill = 999.0;
}

abstract final class KairoTheme {
  static const _displayFamily = 'Dela Gothic One';
  static const _bodyFamily = 'Zen Kaku Gothic New';

  /// Display style for screen titles and the logo.
  static TextStyle display(BuildContext context, {double size = 26}) =>
      TextStyle(fontFamily: _displayFamily, fontSize: size, color: KairoColors.text, height: 1.15);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: KairoColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: KairoColors.primary,
      onPrimary: KairoColors.text,
      secondary: KairoColors.accent,
      tertiary: KairoColors.info,
      surface: KairoColors.background,
      onSurface: KairoColors.text,
      outline: KairoColors.outline,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _bodyFamily,
      scaffoldBackgroundColor: KairoColors.background,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: KairoColors.text,
        displayColor: KairoColors.text,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: KairoColors.primarySoft),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: KairoColors.surface,
        showDragHandle: true,
        dragHandleColor: KairoColors.outline,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KairoRadii.hero))),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(backgroundColor: WidgetStatePropertyAll(KairoColors.surfaceRaised)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: KairoColors.background,
        foregroundColor: KairoColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: KairoColors.navBar,
        indicatorColor: KairoColors.primary.withValues(alpha: 0.22),
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? KairoColors.primarySoft : KairoColors.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: _bodyFamily,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? KairoColors.primarySoft : KairoColors.textSecondary,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: KairoColors.primary,
          foregroundColor: KairoColors.text,
          minimumSize: const Size(0, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: _bodyFamily, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: KairoColors.text,
          minimumSize: const Size(0, 44),
          shape: const StadiumBorder(),
          side: const BorderSide(color: KairoColors.outline),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: KairoColors.surfaceRaised,
        contentTextStyle: TextStyle(fontFamily: _bodyFamily, color: KairoColors.text),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? KairoColors.primary : KairoColors.outline,
        ),
        thumbColor: const WidgetStatePropertyAll(KairoColors.text),
      ),
    );
  }
}

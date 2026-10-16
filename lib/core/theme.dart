import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  /// Display style for screen titles and the logo.
  static TextStyle display(BuildContext context, {double size = 26}) {
    final useGoogle = Theme.of(context).extension<_FontFlag>()?.useGoogleFonts ?? false;
    final base = TextStyle(fontSize: size, color: KairoColors.text, height: 1.15);
    return useGoogle ? GoogleFonts.delaGothicOne(textStyle: base) : base.copyWith(fontFamily: _displayFamily);
  }

  static ThemeData dark({bool useGoogleFonts = true}) {
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
      scaffoldBackgroundColor: KairoColors.background,
      extensions: [_FontFlag(useGoogleFonts)],
    );

    final textTheme = useGoogleFonts
        ? GoogleFonts.getTextTheme('Zen Kaku Gothic New', base.textTheme)
        : base.textTheme;

    return base.copyWith(
      textTheme: textTheme.apply(
        bodyColor: KairoColors.text,
        displayColor: KairoColors.text,
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
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? KairoColors.primarySoft : KairoColors.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
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
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
        contentTextStyle: TextStyle(color: KairoColors.text),
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

class _FontFlag extends ThemeExtension<_FontFlag> {
  const _FontFlag(this.useGoogleFonts);

  final bool useGoogleFonts;

  @override
  _FontFlag copyWith({bool? useGoogleFonts}) => _FontFlag(useGoogleFonts ?? this.useGoogleFonts);

  @override
  _FontFlag lerp(_FontFlag? other, double t) => other ?? this;
}

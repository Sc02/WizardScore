import 'package:flutter/material.dart';

import 'palette.dart';

/// The app theme: deep purple felt with gold accents, matching the gold crown
/// and the word WINNER on the winner screen.
ThemeData buildWizardTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: WizardColors.felt,
        brightness: Brightness.dark,
      ).copyWith(
        primary: WizardColors.goldMid,
        secondary: WizardColors.goldLight,
        surface: WizardColors.feltDark,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WizardColors.feltDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: WizardColors.felt,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: WizardColors.felt,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WizardColors.goldMid,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WizardColors.goldLight,
        side: const BorderSide(color: WizardColors.goldDark),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WizardColors.goldMid, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: WizardColors.felt,
      indicatorColor: WizardColors.goldMid.withValues(alpha: 0.25),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    ),
    dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.08)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: WizardColors.felt,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Big gold text, used for the word WINNER.
class GoldGradientText extends StatelessWidget {
  const GoldGradientText(
    this.text, {
    this.fontSize = 48,
    this.letterSpacing = 8,
    super.key,
  });

  final String text;
  final double fontSize;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          WizardColors.goldLight,
          WizardColors.goldMid,
          WizardColors.goldDark,
        ],
        stops: <double>[0, 0.5, 1],
      ).createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          letterSpacing: letterSpacing,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

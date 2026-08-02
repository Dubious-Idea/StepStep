import 'package:flutter/material.dart';

/// Design tokens for StepStep — "dark luxury": a graphite base that stays out
/// of the way, one signature neon gradient that carries all the energy, and a
/// gold state reserved for the moment the daily goal is beaten.
///
/// Nothing here is decorative-only: every accent maps to a meaning
/// (progress, calories, distance, goal reached).
abstract final class AppColors {
  // Base surfaces — near-black with a cool cast so the neon reads warmer.
  static const Color background = Color(0xFF08090C);
  static const Color surface = Color(0xFF111319);
  static const Color surfaceRaised = Color(0xFF181B23);
  static const Color stroke = Color(0xFF232733);
  static const Color strokeSoft = Color(0xFF1A1D25);

  // Text ramp.
  static const Color textPrimary = Color(0xFFF4F5F7);
  static const Color textSecondary = Color(0xFF8A90A0);
  static const Color textMuted = Color(0xFF565C6B);

  // Signature progress gradient: lime -> mint -> blue.
  static const Color accentStart = Color(0xFFA8FF3E);
  static const Color accentMid = Color(0xFF22E8B4);
  static const Color accentEnd = Color(0xFF4C7BFF);

  /// Reserved for "goal reached" — never used decoratively.
  static const Color gold = Color(0xFFFFC94A);

  /// Semantic stat colours.
  static const Color calories = Color(0xFFFF7A45);
  static const Color distance = Color(0xFF4C7BFF);
  static const Color activeTime = Color(0xFF22E8B4);

  static const List<Color> ringGradient = [
    accentStart,
    accentMid,
    accentEnd,
    accentStart,
  ];

  static const List<Color> goalReachedGradient = [
    gold,
    Color(0xFFFFE9A8),
    gold,
    Color(0xFFFFB020),
  ];
}

/// Spacing scale. Deliberately uneven at the top end — sections breathe more
/// than the elements inside them, which is what stops the layout reading as a
/// uniform card grid.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 36;
  static const double section = 52;

  static const double screenPadding = 20;
}

abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 18;
  static const double lg = 26;
  static const double pill = 999;
}

abstract final class AppDuration {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 340);
  static const Duration ring = Duration(milliseconds: 900);
  static const Duration counter = Duration(milliseconds: 700);
}

abstract final class AppCurves {
  /// Fast out, slow settle — motion that clarifies rather than bounces.
  static const Curve outExpo = Cubic(0.16, 1, 0.3, 1);
  static const Curve inOut = Curves.easeInOutCubic;
}

/// Text styles. The hierarchy is carried by *scale contrast* — a 68px display
/// figure against 11px uppercase labels — rather than by many colours.
abstract final class AppText {
  /// Tabular figures keep the big counter from jittering as digits change.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static const TextStyle display = TextStyle(
    fontSize: 68,
    height: 1.0,
    fontWeight: FontWeight.w300,
    letterSpacing: -2.5,
    color: AppColors.textPrimary,
    fontFeatures: _tabular,
  );

  static const TextStyle statValue = TextStyle(
    fontSize: 26,
    height: 1.1,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
    fontFeatures: _tabular,
  );

  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Small uppercase caption — the counterweight to the display figure.
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: AppColors.textMuted,
  );

  static const TextStyle labelBright = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: AppColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: AppColors.background,
  );
}

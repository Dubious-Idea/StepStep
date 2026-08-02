import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// The app is dark by design direction, not by system preference — a graphite
/// canvas is what makes the neon ring read as light rather than as paint.
ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    surface: AppColors.background,
    onSurface: AppColors.textPrimary,
    primary: AppColors.accentMid,
    onPrimary: AppColors.background,
    secondary: AppColors.accentStart,
    onSecondary: AppColors.background,
    outline: AppColors.stroke,
    error: Color(0xFFFF6B6B),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accentMid,
      selectionColor: Color(0x3322E8B4),
      selectionHandleColor: AppColors.accentMid,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.title,
      iconTheme: IconThemeData(color: AppColors.textSecondary),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accentMid,
      inactiveTrackColor: AppColors.stroke,
      thumbColor: AppColors.textPrimary,
      overlayColor: Color(0x2222E8B4),
      trackHeight: 3,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.strokeSoft,
      thickness: 1,
      space: 1,
    ),
  );
}

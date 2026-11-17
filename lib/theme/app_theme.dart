import 'package:flutter/material.dart';

/// Design tokens of the "High-Voltage" system (see
/// design/mockups-stitch/stitch_lidl_gift_card_tracker/high_voltage_value/DESIGN.md):
/// Lidl blue anchors, high-voltage yellow actions, urgency red for expiries.
abstract final class AppColors {
  // Brand.
  static const Color blue = Color(0xFF0050AA);
  static const Color blueDark = Color(0xFF003B7E);
  static const Color blueLight = Color(0xFF2E6FC2);
  static const Color yellow = Color(0xFFFFF000);
  static const Color yellowDark = Color(0xFFB7A900);
  static const Color red = Color(0xFFE30613);
  static const Color redContainer = Color(0xFFFFE6E3);

  // Neutrals.
  static const Color slate = Color(0xFF1E293B);
  static const Color slateMuted = Color(0xFF5A6B85);
  static const Color background = Color(0xFFF4F6F9);
  static const Color outline = Color(0xFFE5E9F0);
  static const Color chipBlue = Color(0xFFE7EEFF);
  static const Color chipBlueDeep = Color(0xFFD8E3FB);

  /// Hero card gradient: light blue top-left fading into Lidl blue.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blueLight, blue, blueDark],
    stops: [0.0, 0.55, 1.0],
  );

  /// Level-2 elevation: bright ambient glow instead of a murky shadow.
  static const List<BoxShadow> cardGlow = [
    BoxShadow(
      offset: Offset(0, 10),
      blurRadius: 24,
      spreadRadius: -4,
      color: Color(0x140050AA),
    ),
    BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 8,
      spreadRadius: -2,
      color: Color(0x0A1E293B),
    ),
  ];
}

/// Corner radii scale (pill-first geometry).
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double hero = 48;
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// Spacing scale, multiples of 4px.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 36;
}

/// Builds the app-wide [ThemeData]: Space Grotesk for display/numeric roles,
/// DM Sans for body copy, white pill cards on the light slate canvas.
ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.blue,
    onPrimary: Colors.white,
    primaryContainer: AppColors.chipBlueDeep,
    onPrimaryContainer: Color(0xFF003575),
    secondary: AppColors.yellow,
    onSecondary: AppColors.slate,
    secondaryContainer: AppColors.yellow,
    onSecondaryContainer: AppColors.slate,
    tertiary: AppColors.red,
    onTertiary: Colors.white,
    tertiaryContainer: AppColors.redContainer,
    onTertiaryContainer: Color(0xFFB0000C),
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    surface: Colors.white,
    onSurface: AppColors.slate,
    onSurfaceVariant: AppColors.slateMuted,
    outline: AppColors.outline,
    outlineVariant: AppColors.outline,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: AppColors.background,
    surfaceContainer: Color(0xFFEDF0F6),
    surfaceContainerHigh: AppColors.chipBlue,
    surfaceContainerHighest: AppColors.chipBlueDeep,
    inverseSurface: Color(0xFF0D1520),
    onInverseSurface: Colors.white,
    inversePrimary: AppColors.yellow,
    surfaceTint: Colors.transparent,
  );

  const grotesk = 'Space Grotesk';
  const dmSans = 'DM Sans';

  TextTheme buildTextTheme(Color onSurface, Color onSurfaceVariant) {
    return TextTheme(
      displayLarge: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w700,
          fontSize: 44,
          height: 1.05,
          letterSpacing: -1.5,
          color: onSurface),
      displayMedium: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w700,
          fontSize: 34,
          height: 1.1,
          letterSpacing: -1,
          color: onSurface),
      displaySmall: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w700,
          fontSize: 28,
          height: 1.15,
          letterSpacing: -0.8,
          color: onSurface),
      headlineLarge: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w700,
          fontSize: 26,
          height: 1.2,
          letterSpacing: -0.5,
          color: onSurface),
      headlineMedium: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w600,
          fontSize: 22,
          height: 1.25,
          letterSpacing: -0.3,
          color: onSurface),
      headlineSmall: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w600,
          fontSize: 18,
          height: 1.3,
          color: onSurface),
      titleLarge: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          height: 1.3,
          color: onSurface),
      titleMedium: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
          height: 1.3,
          color: onSurface),
      titleSmall: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w500,
          fontSize: 13,
          height: 1.3,
          color: onSurface),
      bodyLarge: TextStyle(
          fontFamily: dmSans, fontWeight: FontWeight.w400, fontSize: 16, height: 1.45, color: onSurface),
      bodyMedium: TextStyle(
          fontFamily: dmSans, fontWeight: FontWeight.w400, fontSize: 14, height: 1.4, color: onSurface),
      bodySmall: TextStyle(
          fontFamily: dmSans,
          fontWeight: FontWeight.w400,
          fontSize: 12,
          height: 1.35,
          color: onSurfaceVariant),
      labelLarge: TextStyle(
          fontFamily: grotesk, fontWeight: FontWeight.w600, fontSize: 14, height: 1.2, color: onSurface),
      labelMedium: TextStyle(
          fontFamily: grotesk, fontWeight: FontWeight.w600, fontSize: 12, height: 1.2, color: onSurface),
      labelSmall: TextStyle(
          fontFamily: grotesk,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          height: 1.2,
          letterSpacing: 0.4,
          color: onSurface),
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: buildTextTheme(scheme.onSurface, scheme.onSurfaceVariant),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
        fontFamily: grotesk,
        fontWeight: FontWeight.w600,
        fontSize: 20,
        color: AppColors.slate,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.slate,
        disabledBackgroundColor: AppColors.yellow.withValues(alpha: 0.45),
        disabledForegroundColor: AppColors.slate.withValues(alpha: 0.5),
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
            fontFamily: grotesk, fontWeight: FontWeight.w600, fontSize: 15.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blue,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        side: const BorderSide(color: AppColors.blue, width: 1.6),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
            fontFamily: grotesk, fontWeight: FontWeight.w600, fontSize: 15.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue,
        textStyle: const TextStyle(
            fontFamily: grotesk, fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: AppColors.yellow,
      side: const BorderSide(color: AppColors.outline),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
          fontFamily: grotesk, fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.slate),
      secondaryLabelStyle: const TextStyle(
          fontFamily: grotesk, fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.slate),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: AppColors.blue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 2),
      ),
      hintStyle: const TextStyle(fontFamily: dmSans, fontSize: 14, color: AppColors.slateMuted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.yellow,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppColors.slate
                : AppColors.slateMuted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: grotesk,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
            color: states.contains(WidgetState.selected)
                ? AppColors.slate
                : AppColors.slateMuted,
          )),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      modalBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      showDragHandle: true,
      dragHandleColor: AppColors.outline,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      titleTextStyle: const TextStyle(
          fontFamily: grotesk, fontWeight: FontWeight.w600, fontSize: 18, color: AppColors.slate),
      contentTextStyle: const TextStyle(
          fontFamily: dmSans, fontSize: 14, height: 1.4, color: AppColors.slate),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.slate,
      contentTextStyle: const TextStyle(fontFamily: dmSans, fontSize: 14, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.yellow,
      linearTrackColor: AppColors.chipBlueDeep,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.yellow,
      foregroundColor: AppColors.slate,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.blue : Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.chipBlueDeep : AppColors.outline),
    ),
  );
}

import 'package:flutter/material.dart';

class AppTheme {
  // ── Tactical Color Palette ──────────────────────────────────────────────────
  static const Color bgPrimary    = Color(0xFF080C0A); // near-black with green tint
  static const Color bgSecondary  = Color(0xFF0D1410); // slightly lighter dark
  static const Color bgCard       = Color(0xFF111A14); // card surface
  static const Color bgSurface    = Color(0xFF162019); // elevated surface
  static const Color bgOverlay    = Color(0xFF0A120D); // panel overlay

  // Tactical green accents
  static const Color greenPrimary = Color(0xFF2D7A3A); // base green
  static const Color greenAccent  = Color(0xFF39D353); // bright accent green
  static const Color greenLight   = Color(0xFF76FF03); // highlight green
  static const Color greenDim     = Color(0xFF1B4D25); // muted green

  // Text
  static const Color textPrimary   = Color(0xFFD0E8D4); // soft green-white
  static const Color textSecondary = Color(0xFF6EA87A); // muted green
  static const Color textMuted     = Color(0xFF3A5C41); // very muted
  static const Color textLabel     = Color(0xFF4D8C5A); // label text

  // Borders & lines
  static const Color borderColor   = Color(0xFF1E3524); // subtle green border
  static const Color borderBright  = Color(0xFF2D7A3A); // active border

  // Status colors
  static const Color errorColor    = Color(0xFFFF4444);
  static const Color warningColor  = Color(0xFFFFB300);
  static const Color infoColor     = Color(0xFF29B6F6);
  static const Color successColor  = Color(0xFF39D353);

  // FAB colors (tactical muted palette)
  static const Color gradientStart = Color(0xFF1B4D25);
  static const Color gradientEnd   = Color(0xFF0D1410);
  static const Color fabZoom       = Color(0xFF2D7A3A);
  static const Color fabLocation   = Color(0xFF39D353);
  static const Color fabDownload   = Color(0xFF29B6F6);
  static const Color fabTrack      = Color(0xFFFFB300);
  static const Color fabImport     = Color(0xFF26A69A);
  static const Color fabCoords     = Color(0xFFEF5350);
  static const Color fabPdf        = Color(0xFFAB47BC);
  static const Color fabCamera     = Color(0xFF39D353);

  // Aliases
  static const Color primaryColor  = greenPrimary;
  static const Color accentColor   = greenAccent;

  // Text style shortcuts
  static const TextStyle bodyMedium = TextStyle(
    color: textPrimary, fontSize: 13, fontFamily: 'monospace',
  );
  static const TextStyle bodySmall = TextStyle(
    color: textSecondary, fontSize: 11, fontFamily: 'monospace',
  );

  // InputDecoration helper
  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    IconData? prefixIcon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: textSecondary, size: 18)
          : null,
      suffix: suffix,
      filled: true,
      fillColor: bgSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: greenAccent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textSecondary, fontFamily: 'monospace'),
      hintStyle: const TextStyle(color: textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  // Polygon colors (tactical palette)
  static const List<Color> polygonColors = [
    Color(0xFF39D353),
    Color(0xFF29B6F6),
    Color(0xFFFF4444),
    Color(0xFFFFB300),
    Color(0xFFAB47BC),
    Color(0xFF76FF03),
    Color(0xFFFF7043),
    Color(0xFF26C6DA),
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: greenAccent,
        secondary: greenLight,
        tertiary: greenPrimary,
        surface: bgSecondary,
        error: errorColor,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: textPrimary,
        outline: borderColor,
      ),
      scaffoldBackgroundColor: bgPrimary,
      fontFamily: 'monospace',
      appBarTheme: const AppBarTheme(
        backgroundColor: bgSecondary,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: greenAccent,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
          fontFamily: 'monospace',
        ),
        iconTheme: IconThemeData(color: greenAccent),
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgSecondary,
        selectedItemColor: greenAccent,
        unselectedItemColor: textMuted,
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 1.5,
          fontFamily: 'monospace',
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 9,
          letterSpacing: 1.0,
          fontFamily: 'monospace',
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: borderColor, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: greenPrimary,
        foregroundColor: greenAccent,
        elevation: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: greenPrimary,
          foregroundColor: greenAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: greenAccent, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: greenAccent,
          side: const BorderSide(color: greenAccent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: greenAccent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: greenAccent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      dividerTheme: const DividerThemeData(color: borderColor, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgSurface,
        contentTextStyle: const TextStyle(
          color: greenAccent,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: borderColor),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgSurface,
        selectedColor: greenPrimary.withOpacity(0.4),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
        side: const BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      textTheme: const TextTheme(
        displayLarge:  TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
        displayMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
        headlineLarge: TextStyle(color: greenAccent,  fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 2),
        headlineMedium:TextStyle(color: greenAccent,  fontWeight: FontWeight.w600, fontFamily: 'monospace', letterSpacing: 1.5),
        headlineSmall: TextStyle(color: textPrimary,  fontWeight: FontWeight.w600, fontFamily: 'monospace'),
        titleLarge:    TextStyle(color: textPrimary,  fontWeight: FontWeight.w600, fontFamily: 'monospace'),
        titleMedium:   TextStyle(color: textPrimary,  fontWeight: FontWeight.w500, fontFamily: 'monospace'),
        titleSmall:    TextStyle(color: textSecondary, fontFamily: 'monospace'),
        bodyLarge:     TextStyle(color: textPrimary,  fontFamily: 'monospace'),
        bodyMedium:    TextStyle(color: textSecondary, fontFamily: 'monospace'),
        bodySmall:     TextStyle(color: textMuted,    fontSize: 11, fontFamily: 'monospace'),
        labelLarge:    TextStyle(color: textPrimary,  fontWeight: FontWeight.w500, fontFamily: 'monospace'),
        labelMedium:   TextStyle(color: textSecondary, fontFamily: 'monospace'),
        labelSmall:    TextStyle(color: textMuted,    fontSize: 10, fontFamily: 'monospace'),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class C {
  static const primary = Color(0xFF1E88E5);
  static const primarySoft = Color(0xFFE8F3FD);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const line = Color(0xFFE5E7EB);
  static const bg = Color(0xFFF6F8FB);
  static const red = Color(0xFFDC2626);
  static const redSoft = Color(0xFFFDECEC);
  static const amber = Color(0xFFB45309);
  static const amberSoft = Color(0xFFFEF3E2);
  static const green = Color(0xFF16A34A);
  static const greenSoft = Color(0xFFE7F6EC);
}

TextStyle ts(double size, {FontWeight w = FontWeight.w400, Color color = C.ink, double? ls, double? h}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: color, letterSpacing: ls, height: h);

ThemeData appTheme() {
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: C.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: C.primary, primary: C.primary),
    textTheme: GoogleFonts.interTextTheme().apply(bodyColor: C.ink, displayColor: C.ink),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          backgroundColor: C.primary, foregroundColor: Colors.white, minimumSize: const Size(0, 44), shape: shape, textStyle: ts(14, w: FontWeight.w600)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          foregroundColor: C.ink, side: const BorderSide(color: C.line), minimumSize: const Size(0, 44), shape: shape, textStyle: ts(14, w: FontWeight.w600)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: C.muted, textStyle: ts(14, w: FontWeight.w600))),
  );
}

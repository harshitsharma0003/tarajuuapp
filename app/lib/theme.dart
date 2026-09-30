import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colour tokens — 1:1 with the prototype's CSS `:root` variables.
class T {
  static const amber = Color(0xFFD97706);
  static const amberDark = Color(0xFF78350F);
  static const amberLight = Color(0xFFF59E0B);
  static const amberPale = Color(0xFFFEF3C7);
  static const amberBorder = Color(0xFFFCD34D);
  static const bg = Color(0xFFFFFBEB);
  static const gray = Color(0xFF888888);
  static const text = Color(0xFF222222);
  static const green = Color(0xFF15803D);
  static const greenBg = Color(0xFFDCFCE7);
  static const blue = Color(0xFF1D4ED8);
  static const blueBg = Color(0xFFDBEAFE);
  static const red = Color(0xFFE24B4A);

  static const soft = Color(0xFFF5F5F3); // page background on Home/Confirm
  static const line = Color(0xFFF0F0EE); // hairlines
  static const tileBg = Color(0xFFF8F8F6);
  static const ink = Color(0xFF111111);

  // Platform tags (AMZ / FLK)
  static const amzBg = Color(0xFFFAEEDA);
  static const amzFg = Color(0xFF78350F);
  static const fkBg = Color(0xFFDBEAFE);
  static const fkFg = Color(0xFF1E3A8A);

  // Dark hero on Home
  static const heroTop = Color(0xFF0F1923);
  static const heroMid = Color(0xFF111D2E);
  static const heroBottom = Color(0xFF1A2A3F);

  static const productImageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFEF9EE), Color(0xFFFFFBEB)],
  );
}

/// Poppins = body font, Nunito = display font (both as in the prototype).
TextStyle pop(double size, {FontWeight w = FontWeight.w400, Color c = T.text, double? h, TextDecoration? deco, double? ls}) =>
    GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c, height: h, decoration: deco, decorationColor: c, letterSpacing: ls);

TextStyle nun(double size, {FontWeight w = FontWeight.w800, Color c = T.text, double? h, double? ls}) =>
    GoogleFonts.nunito(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: T.amber, primary: T.amber),
    scaffoldBackgroundColor: Colors.white,
  );
  return base.copyWith(
    textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
    splashFactory: InkRipple.splashFactory,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: T.ink,
      behavior: SnackBarBehavior.floating,
      contentTextStyle: pop(12, w: FontWeight.w600, c: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

/// ₹ formatting with Indian digit grouping (1,23,456) — same as toLocaleString('en-IN').
String inr(num? n) {
  if (n == null) return 'N/A';
  final s = n.round().toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

String compactCount(int? n) {
  if (n == null) return '';
  if (n >= 100000) return '${(n / 100000).toStringAsFixed(1)}L';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

import 'package:flutter/material.dart';

const paper = Color(0xFFF4F3EB);
const ink = Color(0xFF1B211D);
const lime = Color(0xFFD4F568);
const muted = Color(0xFF646C65);
const rule = Color(0xFFD5D9CE);
const danger = Color(0xFF9D3028);
const moneyFeatures = <FontFeature>[FontFeature.tabularFigures()];

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'GolosText',
  scaffoldBackgroundColor: paper,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: ink,
        brightness: Brightness.light,
      ).copyWith(
        primary: ink,
        onPrimary: Colors.white,
        secondary: lime,
        surface: paper,
        onSurface: ink,
        error: danger,
      ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(
      fontSize: 56,
      height: 1.05,
      fontWeight: FontWeight.w600,
      letterSpacing: -2.5,
    ),
    headlineLarge: TextStyle(
      fontSize: 36,
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: -1.2,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -.7,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -.4,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w500,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    bodySmall: TextStyle(fontSize: 12, height: 1.5),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: .8,
    ),
  ).apply(bodyColor: ink, displayColor: ink),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: ink,
      foregroundColor: Colors.white,
      minimumSize: const Size(48, 52),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
        fontFamily: 'GolosText',
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      minimumSize: const Size(48, 50),
      side: const BorderSide(color: rule),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: ink,
      minimumSize: const Size(48, 48),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: ink,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white.withValues(alpha: .7),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: rule),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: rule),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: ink, width: 1.5),
    ),
    labelStyle: const TextStyle(color: muted),
  ),
  dividerTheme: const DividerThemeData(color: rule, thickness: 1, space: 1),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: ink,
    contentTextStyle: const TextStyle(
      color: Colors.white,
      fontFamily: 'GolosText',
    ),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(9),
        ),
        child: CustomPaint(painter: _RouteMark()),
      ),
      const SizedBox(width: 11),
      const Text(
        'СМЕНА',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    ],
  );
}

class _RouteMark extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lime
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(11, 23)
        ..lineTo(20, 23)
        ..quadraticBezierTo(24, 23, 24, 19)
        ..quadraticBezierTo(24, 15, 20, 15)
        ..lineTo(14, 15)
        ..quadraticBezierTo(10, 15, 10, 11),
      paint,
    );
    canvas.drawCircle(const Offset(10, 10), 2.4, Paint()..color = lime);
  }

  @override
  bool shouldRepaint(_RouteMark oldDelegate) => false;
}

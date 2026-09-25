import 'package:flutter/material.dart';

/// The launcher icon's shopping-bag glyph, redrawn from the same path data as
/// `android/app/src/main/res/drawable/ic_launcher_foreground.xml` (108x108
/// viewport, glyph pre-centered at (54,54)) — there is no Flutter-usable
/// asset for it, and the Material `shopping_bag_rounded` icon is a visibly
/// different shape. This is the app's actual brand mark; use it anywhere the
/// app's own logo belongs (splash/loading screens, the login screen, a top
/// bar) instead of a generic Material icon standing in for it.
class AppIconGlyph extends StatelessWidget {
  const AppIconGlyph({super.key, required this.height, required this.color});

  /// Rendered height of the glyph's own ink — not the 108x108 viewport,
  /// which is padded out to the adaptive-icon safe zone and isn't relevant
  /// once this is just a mark on a screen rather than a launcher icon.
  final double height;
  final Color color;

  /// The glyph's bounding box within that 108x108 viewport.
  static const _bounds = Rect.fromLTRB(33.19, 29.64, 74.81, 78.36);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * _bounds.width / _bounds.height,
      height: height,
      child: CustomPaint(painter: _BagGlyphPainter(color)),
    );
  }
}

class _BagGlyphPainter extends CustomPainter {
  _BagGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final bounds = AppIconGlyph._bounds;
    final scale = size.height / bounds.height;
    canvas.save();
    canvas.translate(-bounds.left * scale, -bounds.top * scale);
    canvas.scale(scale);
    canvas.drawPath(_handle, paint);
    canvas.drawPath(_body, paint);
    canvas.restore();
  }

  Path get _handle => Path()
    ..moveTo(54, 29.64)
    ..cubicTo(50.33, 29.64, 47.49, 31.52, 45.67, 34.02)
    ..cubicTo(44.42, 35.74, 43.62, 37.75, 43.24, 39.72)
    ..lineTo(45.18, 39.72)
    ..cubicTo(45.54, 38.12, 46.22, 36.49, 47.21, 35.13)
    ..cubicTo(48.75, 33.01, 50.96, 31.53, 54, 31.53)
    ..cubicTo(57.05, 31.53, 59.25, 33.01, 60.79, 35.13)
    ..cubicTo(61.78, 36.49, 62.46, 38.12, 62.82, 39.72)
    ..lineTo(64.76, 39.72)
    ..cubicTo(64.38, 37.75, 63.58, 35.74, 62.33, 34.02)
    ..cubicTo(60.51, 31.52, 57.68, 29.64, 54, 29.64)
    ..close();

  Path get _body => Path()
    ..moveTo(36.39, 41.61)
    ..lineTo(33.19, 78.36)
    ..lineTo(74.81, 78.36)
    ..lineTo(71.62, 41.61)
    ..close();

  @override
  bool shouldRepaint(covariant _BagGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

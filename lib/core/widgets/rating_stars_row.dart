import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Five-star display for product ratings (0–5) with smooth partial fills; optional compact numeric score.
class RatingStarsRow extends StatelessWidget {
  const RatingStarsRow({
    super.key,
    required this.rating,
    this.size = 13,
    this.gap = 2,
    this.showNumeric = true,
  });

  final double rating;
  final double size;
  final double gap;
  final bool showNumeric;

  static const Color _fill = Color(0xFFFFB300);
  static final Color _empty = AppColors.hint.withValues(alpha: 0.55);

  @override
  Widget build(BuildContext context) {
    final r = rating.isNaN || rating.isInfinite ? 0.0 : rating.clamp(0.0, 5.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (int i = 0; i < 5; i++) ...[
          if (i > 0) SizedBox(width: gap),
          _StarSlot(
            fill: (r - i).clamp(0.0, 1.0),
            size: size,
            fillColor: _fill,
            emptyColor: _empty,
          ),
        ],
        if (showNumeric) ...[
          const SizedBox(width: 5),
          Text(
            r.toStringAsFixed(1),
            style: TextStyle(
              fontSize: (size * 0.9).clamp(9.0, 11.5),
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              height: 1.1,
            ),
          ),
        ],
      ],
    );
  }
}

class _StarSlot extends StatelessWidget {
  const _StarSlot({
    required this.fill,
    required this.size,
    required this.fillColor,
    required this.emptyColor,
  });

  final double fill;
  final double size;
  final Color fillColor;
  final Color emptyColor;

  @override
  Widget build(BuildContext context) {
    if (fill >= 0.999) {
      return Icon(Icons.star_rounded, size: size, color: fillColor);
    }
    if (fill <= 0.001) {
      return Icon(Icons.star_rounded, size: size, color: emptyColor);
    }
    // [Align+widthFactor] on [Icon] does not reliably clip partial stars (e.g. 1.8 read as
    // 2 full). Clip the amber layer to a left fraction in the icon’s layout space.
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Icon(Icons.star_rounded, size: size, color: emptyColor),
          ClipPath(
            clipper: _StarLeftFillClipper(fraction: fill),
            child: Icon(Icons.star_rounded, size: size, color: fillColor),
          ),
        ],
      ),
    );
  }
}

/// Rectangular left strip over the same-sized star (correct for Material star glyph).
class _StarLeftFillClipper extends CustomClipper<Path> {
  _StarLeftFillClipper({required this.fraction});
  final double fraction;

  @override
  Path getClip(Size size) {
    final w = (size.width * fraction.clamp(0.0, 1.0));
    return Path()..addRect(Rect.fromLTWH(0, 0, w, size.height));
  }

  @override
  bool shouldReclip(covariant _StarLeftFillClipper old) =>
      old.fraction != fraction;
}

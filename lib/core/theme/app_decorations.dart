import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppDecorations {
  /// Yumuşak, yayılmış kart gölgesi (ürün kartları, yüzen yüzeyler).
  static List<BoxShadow> softCardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 24,
      spreadRadius: 0,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 8,
      spreadRadius: 0,
      offset: const Offset(0, 2),
    ),
  ];

  static BoxDecoration productCard = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(16),
    boxShadow: softCardShadow,
  );

  /// Birincil tonlu kartlar (ör. top ürün şeridi).
  static List<BoxShadow> softPrimaryGlow(Color primary) => [
        BoxShadow(
          color: primary.withValues(alpha: 0.22),
          blurRadius: 20,
          spreadRadius: -2,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static BorderRadius cardRadius = BorderRadius.circular(16);

  static const double cardRadiusValue = 16;
}

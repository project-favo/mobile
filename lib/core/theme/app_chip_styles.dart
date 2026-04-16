import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppChipStyles {
  static BoxDecoration categoryChipDecoration({bool selected = false}) {
    return BoxDecoration(
      color: selected ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: selected ? AppColors.primary : AppColors.textSecondary.withOpacity(0.28),
        width: 1,
      ),
      boxShadow: selected
          ? [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 18,
                spreadRadius: -2,
                offset: const Offset(0, 6),
              ),
            ]
          : [],
    );
  }

  /// Alt kategori: gölge yok — köşede gölge taşması / kirli görünümü önler.
  static BoxDecoration subCategoryChipDecoration({bool selected = false}) {
    return BoxDecoration(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.12)
          : Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: selected ? AppColors.primary : AppColors.border,
        width: 1,
      ),
    );
  }

  static TextStyle categoryChipText({bool selected = false}) {
    return TextStyle(
      color: selected ? Colors.white : AppColors.textPrimary,
      fontSize: 13,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: 0.2,
    );
  }

  static TextStyle subCategoryChipText({bool selected = false}) {
    return TextStyle(
      color: selected ? AppColors.primary : AppColors.textPrimary,
      fontSize: 12,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: 0.15,
    );
  }
}

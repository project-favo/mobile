import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppChipStyles {
  static BoxDecoration categoryChipDecoration({bool selected = false}) {
    return BoxDecoration(
      color: selected ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: selected ? AppColors.primary : AppColors.border,
        width: 1.5,
      ),
    );
  }

  static BoxDecoration subCategoryChipDecoration({bool selected = false}) {
    return BoxDecoration(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: selected
            ? AppColors.primary
            : AppColors.textSecondary.withValues(alpha: 0.35),
        width: 1.2,
      ),
    );
  }

  static TextStyle categoryChipText({bool selected = false}) {
    return TextStyle(
      color: selected ? Colors.white : AppColors.textPrimary,
      fontSize: 13,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: 0.1,
    );
  }

  static TextStyle subCategoryChipText({bool selected = false}) {
    return TextStyle(
      color: selected ? AppColors.primary : AppColors.textSecondary,
      fontSize: 12,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      letterSpacing: 0.1,
    );
  }
}

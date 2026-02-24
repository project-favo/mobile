import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppChipStyles {
  static BoxDecoration categoryChipDecoration({bool selected = false}) {
    return BoxDecoration(
      color: selected ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: selected ? AppColors.primary : AppColors.textSecondary.withOpacity(0.3),
        width: 1.2,
      ),
      boxShadow: selected
          ? [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ]
          : [],
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
}

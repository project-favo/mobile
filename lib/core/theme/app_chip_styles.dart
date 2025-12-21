import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppChipStyles {
  static BoxDecoration categoryChipDecoration({bool selected = false}) {
    return BoxDecoration(
      color: selected ? AppColors.primary : AppColors.background,
      borderRadius: selected ? BorderRadius.circular(20) : null,
      border: selected ? Border.all(color: AppColors.primary) : null,
    );
  }

  static TextStyle categoryChipText({bool selected = false}) {
    return TextStyle(
      color: selected ? Colors.white : AppColors.primary,
      fontSize: 14,
      fontWeight: FontWeight.w800,
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';

/// Ürün yorum listesi / satırlarında silme: like & report ile aynı görsel ağırlıkta, sade.
class ReviewInlineDeleteIcon extends StatelessWidget {
  final VoidCallback onTap;

  const ReviewInlineDeleteIcon({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Delete',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Icon(
            Icons.delete_outline_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

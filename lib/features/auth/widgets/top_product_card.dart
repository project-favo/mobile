import 'package:flutter/material.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

class TopProductList extends StatelessWidget {
  final String imageUrl;
  final String title;

  const TopProductList({
    super.key,
    required this.imageUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.productCardWidth,
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: AppDecorations.productCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Product Image
          ClipRRect(
            borderRadius: AppDecorations.cardRadius,
            child: Image.network(
              imageUrl,
              height: AppSpacing.productImageHeight,
              width: AppSpacing.productCardWidth,
              fit: BoxFit.cover,
            ),
          ),

          const SizedBox(height: AppSpacing.medium),

          /// Product Title
          Text(
            title,
            style: AppTextStyles.productTitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

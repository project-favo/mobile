import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_icon_sizes.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_spacing.dart';

class ProductCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String category;
  final double rating;
  final String desc;
  final bool isFavorite;

  const ProductCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.category,
    required this.rating,
    required this.desc,
    this.isFavorite = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.productCardWidth,
      padding: const EdgeInsets.all(12),
      decoration: AppDecorations.productCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ürün resmi
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

          // Title + Favorite Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.productTitle,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: AppColors.primary,
                size: AppIconSizes.favorite,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.small),

          // Category
          Text(
            category.toUpperCase(),
            style: AppTextStyles.productCategory,
          ),

          const SizedBox(height: AppSpacing.large),

          // Rating
          Row(
            children: List.generate(
              5,
                  (index) => Icon(
                index < rating ? Icons.star : Icons.star_border,
                size: AppIconSizes.rating,
                color: AppColors.primary,
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Description
          Text(
            desc,
            style: AppTextStyles.productDesc,
          ),
        ],
      ),
    );
  }
}

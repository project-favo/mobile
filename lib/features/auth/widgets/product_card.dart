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
  final VoidCallback? onTap;

  const ProductCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.category,
    required this.rating,
    required this.desc,
    this.isFavorite = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: AppDecorations.productCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ürün resmi
            Container(
              height: AppSpacing.productImageHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: AppDecorations.cardRadius,
                color: AppColors.background,
              ),
              child: ClipRRect(
                borderRadius: AppDecorations.cardRadius,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.background,
                      child: const Icon(
                        Icons.image_not_supported,
                        color: AppColors.textSecondary,
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.medium),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      title,
                      style: AppTextStyles.productTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: AppColors.primary,
                  size: AppIconSizes.favorite,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.small),

            Text(
              category.toUpperCase(),
              style: AppTextStyles.productCategory,
            ),

            const SizedBox(height: AppSpacing.medium),

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

            const SizedBox(height: 2),

            Text(
              desc,
              style: AppTextStyles.productDesc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}


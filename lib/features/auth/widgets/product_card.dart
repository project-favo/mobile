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
  final VoidCallback? onFavoriteTap;

  const ProductCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.category,
    required this.rating,
    required this.desc,
    this.isFavorite = false,
    this.onTap,
    this.onFavoriteTap,
  });

  @override
  Widget build(BuildContext context) {
    // Debug: Verinin gelip gelmediğini kontrol et
    debugPrint('ProductCard - Ürün: $title, Rating: $rating, Favori: $isFavorite');
    
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
                GestureDetector(
                  onTap: () {
                    if (onFavoriteTap != null) {
                      onFavoriteTap!();
                    }
                  },
                  child: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: AppColors.primary,
                    size: AppIconSizes.favorite,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.small),

            Text(
              category.toUpperCase(),
              style: AppTextStyles.productCategory,
            ),

            const SizedBox(height: AppSpacing.medium),

            // Yıldız gösterimi
            Builder(
              builder: (context) {
                // Rating değerini normalize et
                final rawRating = rating;
                final normalizedRating = (rawRating.isNaN || rawRating.isInfinite || rawRating <= 0) 
                    ? 0.0 
                    : rawRating.clamp(0.0, 5.0);
                
                return Row(
                  children: List.generate(
                    5,
                    (index) {
                      // Tam dolu yıldız kontrolü: rating >= index + 1
                      // Örnek: rating 4.0, index 3 → 4.0 >= 4 → true (4. yıldız dolu)
                      // Örnek: rating 4.0, index 4 → 4.0 >= 5 → false (5. yıldız boş)
                      if (normalizedRating >= index + 1) {
                        return Icon(
                          Icons.star,
                          size: AppIconSizes.rating,
                          color: AppColors.primary,
                        );
                      } 
                      // Yarı dolu yıldız kontrolü: rating > index && rating < index + 1
                      // Örnek: rating 4.5, index 4 → 4.5 > 4 && 4.5 < 5 → true (5. yıldız yarı dolu)
                      else if (normalizedRating > index && normalizedRating < index + 1) {
                        return SizedBox(
                          width: AppIconSizes.rating,
                          height: AppIconSizes.rating,
                          child: Stack(
                            children: [
                              Icon(
                                Icons.star_border,
                                size: AppIconSizes.rating,
                                color: AppColors.textSecondary,
                              ),
                              ClipRect(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: normalizedRating - index,
                                  child: Icon(
                                    Icons.star,
                                    size: AppIconSizes.rating,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } 
                      // Boş yıldız
                      else {
                        return Icon(
                          Icons.star_border,
                          size: AppIconSizes.rating,
                          color: normalizedRating > 0 ? AppColors.textSecondary : AppColors.textSecondary,
                        );
                      }
                    },
                  ),
                );
              },
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


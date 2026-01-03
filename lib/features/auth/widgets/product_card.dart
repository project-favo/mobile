import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_icon_sizes.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../data/repositories/review_repository.dart';

class ProductCard extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String category;
  final double rating;
  final String desc;
  final bool isFavorite;
  final String productId; // Review count için product ID
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteTap;

  const ProductCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.category,
    required this.rating,
    required this.desc,
    required this.productId,
    this.isFavorite = false,
    this.onTap,
    this.onFavoriteTap,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  int? _reviewCount;
  bool _isLoadingReviewCount = false;

  @override
  void initState() {
    super.initState();
    _loadReviewCount();
  }

  Future<void> _loadReviewCount() async {
    setState(() {
      _isLoadingReviewCount = true;
    });

    try {
      final reviewRepository = ReviewRepository();
      final reviews = await reviewRepository.getReviewsByProductId(
        widget.productId,
        firebaseIdToken: null,
      );
      setState(() {
        _reviewCount = reviews.length;
        _isLoadingReviewCount = false;
      });
    } catch (e) {
      setState(() {
        _reviewCount = 0;
        _isLoadingReviewCount = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: AppDecorations.productCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ürün resmi with Hero animation
            Hero(
              tag: 'product_image_${widget.imageUrl}',
              child: Container(
                height: AppSpacing.productImageHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: AppDecorations.cardRadius,
                  color: AppColors.background,
                ),
                child: ClipRRect(
                  borderRadius: AppDecorations.cardRadius,
                  child: Image.network(
                    widget.imageUrl,
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
            ),

            const SizedBox(height: AppSpacing.medium),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      widget.title,
                      style: AppTextStyles.productTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (widget.onFavoriteTap != null) {
                      widget.onFavoriteTap!();
                    }
                  },
                  child: Icon(
                    widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: AppColors.primary,
                    size: AppIconSizes.favorite,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.small),

            Text(
              widget.category.toUpperCase(),
              style: AppTextStyles.productCategory,
            ),

            const SizedBox(height: AppSpacing.medium),

            // Yıldız gösterimi ve rating/review info
            Builder(
              builder: (context) {
                // Rating değerini normalize et
                final rawRating = widget.rating;
                final normalizedRating = (rawRating.isNaN || rawRating.isInfinite || rawRating <= 0) 
                    ? 0.0 
                    : rawRating.clamp(0.0, 5.0);
                
                // Yıldız boyutu küçültüldü (14px)
                const double starSize = 14.0;
                
                return Row(
                  children: [
                    // Stars
                    ...List.generate(
                      5,
                      (index) {
                        // Tam dolu yıldız kontrolü: rating >= index + 1
                        if (normalizedRating >= index + 1) {
                          return const Icon(
                            Icons.star,
                            size: starSize,
                            color: AppColors.primary,
                          );
                        } 
                        // Yarı dolu yıldız kontrolü: rating > index && rating < index + 1
                        else if (normalizedRating > index && normalizedRating < index + 1) {
                          return SizedBox(
                            width: starSize,
                            height: starSize,
                            child: Stack(
                              children: [
                                const Icon(
                                  Icons.star_border,
                                  size: starSize,
                                  color: AppColors.textSecondary,
                                ),
                                ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: normalizedRating - index,
                                    child: const Icon(
                                      Icons.star,
                                      size: starSize,
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
                          return const Icon(
                            Icons.star_border,
                            size: starSize,
                            color: AppColors.textSecondary,
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    // Rating text
                    Text(
                      normalizedRating.toStringAsFixed(1),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 4),
            
            // Review count
            Row(
              children: [
                Icon(
                  Icons.reviews_outlined,
                  size: 12,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  _isLoadingReviewCount
                      ? '...'
                      : '${_reviewCount ?? 0} Reviews',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 2),

            Text(
              widget.desc,
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


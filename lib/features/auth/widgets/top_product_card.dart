import 'package:flutter/material.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/product_rating_display.dart';
import '../../../../core/widgets/new_product_badge.dart';
import '../../../../core/routes/custom_page_transitions.dart';
import '../data/models/product_dto.dart';
import '../presentation/review/pages/review_page.dart';

class TopProductList extends StatefulWidget {
  final ProductDto product;
  final int rank; // 1, 2, 3, etc.

  const TopProductList({
    super.key,
    required this.product,
    required this.rank,
  });

  @override
  State<TopProductList> createState() => _TopProductListState();
}

class _TopProductListState extends State<TopProductList> {
  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final topImgW = (200 * dpr).round().clamp(120, 600);
    final topImgH = (130 * dpr).round().clamp(100, 500);

    final rating = widget.product.averageRating ?? 0.0;
    final showRating = productHasMeaningfulRating(rating);
    final normalizedRating = (rating.isNaN || rating.isInfinite)
        ? 0.0
        : rating.clamp(0.0, 5.0);
    final isLiked = widget.product.isLiked ?? false;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          SlideRightRoute(
            page: ReviewPage(product: widget.product),
          ),
        );
      },
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppDecorations.softPrimaryGlow(AppColors.primary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rank badge and image
            Stack(
              children: [
                // Ürün resmi
                Container(
                  height: 120,
                  width: double.infinity,
                  margin: const EdgeInsets.all(AppSpacing.medium),
                  decoration: BoxDecoration(
                    borderRadius: AppDecorations.cardRadius,
                    color: Colors.white,
                  ),
                  child: ClipRRect(
                    borderRadius: AppDecorations.cardRadius,
                    child: Image.network(
                      widget.product.imageURL,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      cacheWidth: topImgW,
                      cacheHeight: topImgH,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.white,
                          child: const Icon(
                            Icons.image_not_supported,
                            color: AppColors.textSecondary,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Rank badge (sol üst)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${widget.rank}',
                        style: AppTextStyles.bodyBold.copyWith(
                          color: AppColors.primary,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                // Like button (sağ üst)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: isLiked ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),

            // Product info
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.medium,
                0,
                AppSpacing.medium,
                AppSpacing.small,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    widget.product.name,
                    style: AppTextStyles.productTitle.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (showRating) ...[
                    Row(
                      children: [
                        ...List.generate(5, (index) {
                          if (normalizedRating >= index + 1) {
                            return const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.white,
                            );
                          } else if (normalizedRating > index &&
                              normalizedRating < index + 1) {
                            return SizedBox(
                              width: 14,
                              height: 14,
                              child: Stack(
                                children: [
                                  const Icon(
                                    Icons.star_border,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  ClipRect(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: normalizedRating - index,
                                      child: const Icon(
                                        Icons.star,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const Icon(
                            Icons.star_border,
                            size: 14,
                            color: Colors.white70,
                          );
                        }),
                        const SizedBox(width: 6),
                        Text(
                          normalizedRating.toStringAsFixed(1),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ] else ...[
                    const NewProductBadge(onDarkBackground: true),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

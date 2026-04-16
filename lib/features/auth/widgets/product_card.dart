import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_icon_sizes.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/product_rating_display.dart';
import '../../../../core/widgets/new_product_badge.dart';
import '../data/repositories/review_repository.dart';

/// Basit, in-memory review count cache (sadece app çalışırken tutulur).
class _ReviewCountCache {
  static final Map<String, int> _cache = {};

  static int? get(String productId) => _cache[productId];

  static void set(String productId, int count) {
    _cache[productId] = count;
  }
}

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

  /// Grid/listelerde `false` bırakın: her kart için review API çağrısı yapılmaz (çok daha hızlı).
  final bool loadReviewCount;

  const ProductCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.category,
    required this.rating,
    required this.desc,
    required this.productId,
    this.isFavorite = false,
    this.loadReviewCount = false,
    this.onTap,
    this.onFavoriteTap,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  int? _reviewCount;

  @override
  void initState() {
    super.initState();
    if (widget.loadReviewCount) {
      _loadReviewCount();
    }
  }

  Future<void> _loadReviewCount() async {
    // Basit cache: productId -> reviewCount, böylece liste yeniden
    // yüklense bile sayı anında görünür, gidip gelmez.
    _reviewCount = _ReviewCountCache.get(widget.productId);
    try {
      final reviewRepository = ReviewRepository();
      final reviews = await reviewRepository.getReviewsByProductId(
        widget.productId,
        firebaseIdToken: null,
      );
      if (!mounted) return;
      final count = reviews.length;
      _ReviewCountCache.set(widget.productId, count);
      setState(() {
        _reviewCount = count;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reviewCount ??= 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenW = MediaQuery.sizeOf(context).width;
    final imageCacheW =
        ((screenW * 0.55) * dpr).round().clamp(120, 900);
    final imageCacheH =
        (AppSpacing.productImageHeight * dpr).round().clamp(100, 800);

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
              tag: 'product_image_${widget.productId}_${widget.imageUrl}',
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
                    cacheWidth: imageCacheW,
                    cacheHeight: imageCacheH,
                    filterQuality: FilterQuality.medium,
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

            Builder(
              builder: (context) {
                final rawRating = widget.rating;
                if (!productHasMeaningfulRating(rawRating)) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: NewProductBadge(),
                  );
                }
                final normalizedRating = (rawRating.isNaN || rawRating.isInfinite)
                    ? 0.0
                    : rawRating.clamp(0.0, 5.0);
                const double starSize = 14.0;
                return Row(
                  children: [
                    ...List.generate(5, (index) {
                      if (normalizedRating >= index + 1) {
                        return const Icon(
                          Icons.star,
                          size: starSize,
                          color: AppColors.primary,
                        );
                      } else if (normalizedRating > index &&
                          normalizedRating < index + 1) {
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
                      return const Icon(
                        Icons.star_border,
                        size: starSize,
                        color: AppColors.textSecondary,
                      );
                    }),
                    const SizedBox(width: 6),
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

            if (widget.loadReviewCount) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.reviews_outlined,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _reviewCount == null
                        ? 'Reviews'
                        : (_reviewCount == 0
                            ? 'No reviews yet'
                            : '$_reviewCount ${_reviewCount == 1 ? 'review' : 'reviews'}'),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
            ] else
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


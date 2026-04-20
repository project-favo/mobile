import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_icon_sizes.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/product_rating_display.dart';
import '../data/repositories/interaction_repository.dart';
import '../data/repositories/review_repository.dart';

/// Basit, in-memory review count cache (sadece app çalışırken tutulur).
class _ReviewCountCache {
  static final Map<String, int> _cache = {};

  static int? get(String productId) => _cache[productId];

  static void set(String productId, int count) {
    _cache[productId] = count;
  }
}

class _LikeCountCache {
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
  final String? categoryPath;
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
    this.categoryPath,
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
  int? _likeCount;
  static const double _titleBlockHeight = 56;
  static const double _metaRowHeight = 18;

  @override
  void initState() {
    super.initState();
    if (widget.loadReviewCount) {
      _loadSocialCounts();
    }
  }

  Future<void> _loadSocialCounts() async {
    // Basit cache: productId -> reviewCount, böylece liste yeniden
    // yüklense bile sayı anında görünür, gidip gelmez.
    _reviewCount = _ReviewCountCache.get(widget.productId);
    _likeCount = _LikeCountCache.get(widget.productId);
    try {
      final reviewRepository = ReviewRepository();
      final interactionRepository = InteractionRepository();
      final futures = await Future.wait([
        reviewRepository.getReviewsByProductId(
          widget.productId,
          firebaseIdToken: null,
        ),
        interactionRepository.getProductLikeCount(widget.productId),
      ]);
      if (!mounted) return;
      final reviews = futures[0] as List;
      final likeCount = futures[1] as int;
      final count = reviews.length;
      _ReviewCountCache.set(widget.productId, count);
      _LikeCountCache.set(widget.productId, likeCount);
      setState(() {
        _reviewCount = count;
        _likeCount = likeCount;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reviewCount ??= 0;
        _likeCount ??= 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenW = MediaQuery.sizeOf(context).width;
    final imageCacheW =
        ((screenW * 0.55) * dpr).round().clamp(120, 900);
    final imageCacheH = ((screenW * 0.42) * dpr).round().clamp(100, 800);

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
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
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
                      alignment: Alignment.center,
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
            ),

            const SizedBox(height: AppSpacing.medium),

            SizedBox(
              height: _titleBlockHeight,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  widget.title,
                  style: AppTextStyles.productTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            const SizedBox(height: 4),
            SizedBox(
              height: _metaRowHeight,
              child: Builder(
                builder: (context) {
                  final raw = widget.rating;
                  if (!productHasMeaningfulRating(raw)) {
                    return Text(
                      'No rating yet',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }
                  final rating = (raw.isNaN || raw.isInfinite)
                      ? 0.0
                      : raw.clamp(0.0, 5.0);
                  return Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            if (widget.loadReviewCount) ...[
              SizedBox(
                height: _metaRowHeight,
                child: Row(
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_reviewCount ?? 0} review',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_likeCount ?? 0}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: widget.onFavoriteTap,
                      behavior: HitTestBehavior.opaque,
                      child: Icon(
                        widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: widget.isFavorite
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: AppIconSizes.favorite,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: widget.onFavoriteTap,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: widget.isFavorite
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: AppIconSizes.favorite,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}


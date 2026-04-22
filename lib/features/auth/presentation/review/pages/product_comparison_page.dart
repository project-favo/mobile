import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/utils/product_rating_display.dart';
import '../../../../../core/widgets/new_product_badge.dart';
import '../../../../../core/theme/app_decorations.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/repositories/review_repository.dart';
import 'review_page.dart';
import 'review_detail_page.dart';

/// İki ürünü yan yana gösterir: ortalama puan ve yorumlar.
class ProductComparisonPage extends StatefulWidget {
  final ProductDto product1;
  final ProductDto product2;

  const ProductComparisonPage({
    super.key,
    required this.product1,
    required this.product2,
  });

  @override
  State<ProductComparisonPage> createState() => _ProductComparisonPageState();
}

class _ProductComparisonPageState extends State<ProductComparisonPage> {
  final ReviewRepository _reviewRepository = ReviewRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  List<ReviewDto> _reviews1 = [];
  List<ReviewDto> _reviews2 = [];
  bool _loadingReviews = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    String? token;
    try {
      token = await _sessionHelper.getTokenAndSetHeader();
    } catch (_) {}
    try {
      final results = await Future.wait([
        _reviewRepository.getReviewsByProductId(widget.product1.id, firebaseIdToken: token),
        _reviewRepository.getReviewsByProductId(widget.product2.id, firebaseIdToken: token),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews1 = results[0];
        _reviews2 = results[1];
        _loadingReviews = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingReviews = false);
    }
  }

  double _rating(ProductDto p) {
    final r = p.averageRating ?? 0.0;
    return r.isNaN || r.isInfinite ? 0.0 : r.clamp(0.0, 5.0);
  }

  /// true = higher rating (green), false = lower (red). 1 = product1, 2 = product2.
  bool _isWinner(int which) {
    final r1 = _rating(widget.product1);
    final r2 = _rating(widget.product2);
    if (which == 1) return r1 >= r2;
    return r2 > r1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Text(
          'Compare',
          style: AppTextStyles.heading3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ürün kartları sabit kalsın
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildProductCard(widget.product1, _isWinner(1))),
                  Container(
                    width: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: AppColors.textSecondary.withOpacity(0.5),
                  ),
                  Expanded(child: _buildProductCard(widget.product2, _isWinner(2))),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxLarge),
            // Sadece review kısmı scroll olsun
            Expanded(
              child: _loadingReviews
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(child: ReviewCardSkeleton()),
                        const SizedBox(width: AppSpacing.medium),
                        const Expanded(child: ReviewCardSkeleton()),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Center(
                              child: Text(
                                'Reviews',
                                style: AppTextStyles.heading3.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.large),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _buildReviewsSection(
                                    _reviews1,
                                    widget.product1,
                                  ),
                                ),
                                Container(
                                  width: 3,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  color: AppColors.textSecondary
                                      .withOpacity(0.5),
                                ),
                                Expanded(
                                  child: _buildReviewsSection(
                                    _reviews2,
                                    widget.product2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(ProductDto p, bool isWinner) {
    final rating = _rating(p);
    final hasRating = productHasMeaningfulRating(p.averageRating);
    final baseColor = isWinner ? AppColors.success : AppColors.error;
    final cardColor = baseColor.withOpacity(0.06);
    final borderColor = baseColor.withOpacity(0.35);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            SlideRightRoute(page: ReviewPage(product: p)),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.large),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
            boxShadow: AppDecorations.softCardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    p.imageURL,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.textSecondary.withOpacity(0.08),
                      child: const Icon(
                        Icons.image_not_supported,
                        color: AppColors.textSecondary,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.large),
              Text(
                p.name,
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                p.tag.name.toUpperCase(),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.medium),
              if (hasRating)
                Row(
                  children: [
                    const Icon(Icons.star, size: 20, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        rating.toStringAsFixed(1),
                        style: AppTextStyles.heading3.copyWith(color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '/ 5',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                )
              else
                const NewProductBadge(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewsSection(List<ReviewDto> reviews, ProductDto product) {
    final displayList = reviews.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (displayList.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.small),
            child: Text(
              'No reviews yet',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          )
        else
          ...displayList.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.medium),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReviewDetailPage(review: r, product: product),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      height: 160,
                      padding: const EdgeInsets.all(AppSpacing.large),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.ownerUserName,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${r.rating} / 5',
                                  style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(
                              (r.description != null && r.description!.trim().isNotEmpty)
                                  ? r.description!
                                  : r.title,
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
      ],
    );
  }
}

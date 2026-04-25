import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_decorations.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/utils/product_rating_display.dart';
import '../../../../../core/utils/entity_active.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/widgets/new_product_badge.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/repositories/review_repository.dart';
import 'review_page.dart';
import 'review_detail_page.dart';

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
        _reviews1 = filterVisibleReviews(results[0]);
        _reviews2 = filterVisibleReviews(results[1]);
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
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Text(
          'Compare',
          style: AppTextStyles.heading3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xLarge,
          AppSpacing.medium,
          AppSpacing.xLarge,
          AppSpacing.xxLarge + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProductCardsRow(),
            const SizedBox(height: AppSpacing.xLarge),
            _buildRatingBar(),
            const SizedBox(height: AppSpacing.xxLarge),
            _buildReviewsSection(),
          ],
        ),
      ),
    );
  }

  // ── Product cards with floating VS badge ────────────────────────────────────

  Widget _buildProductCardsRow() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildProductCard(widget.product1, _isWinner(1))),
            const SizedBox(width: 44),
            Expanded(child: _buildProductCard(widget.product2, _isWinner(2))),
          ],
        ),
        Positioned(
          top: 52,
          child: _VsBadge(),
        ),
      ],
    );
  }

  Widget _buildProductCard(ProductDto p, bool isWinner) {
    final rating = _rating(p);
    final hasRating = productHasMeaningfulRating(p.averageRating);

    return GestureDetector(
      onTap: () => Navigator.push(context, SlideRightRoute(page: ReviewPage(product: p))),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isWinner
                ? const Color(0xFF22C55E).withOpacity(0.55)
                : AppColors.border.withOpacity(0.45),
            width: 1.5,
          ),
          boxShadow: AppDecorations.softCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  p.imageURL,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.background,
                    child: const Icon(
                      Icons.image_not_supported_rounded,
                      color: AppColors.textSecondary,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    p.tag.name.toUpperCase(),
                    style: AppTextStyles.productCategory.copyWith(fontSize: 9),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  if (hasRating)
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 15, color: AppColors.primary),
                        const SizedBox(width: 3),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Text(
                          '/ 5',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  else
                    const NewProductBadge(),
                  if (isWinner && hasRating) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_events_rounded, size: 11, color: Colors.green.shade700),
                          const SizedBox(width: 3),
                          Text(
                            'Higher rated',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Rating comparison bar ────────────────────────────────────────────────────

  Widget _buildRatingBar() {
    final r1 = _rating(widget.product1);
    final r2 = _rating(widget.product2);
    final has1 = productHasMeaningfulRating(widget.product1.averageRating);
    final has2 = productHasMeaningfulRating(widget.product2.averageRating);
    if (!has1 && !has2) return const SizedBox.shrink();

    final total = r1 + r2;
    final leftFraction = total > 0 ? (r1 / total).clamp(0.05, 0.95) : 0.5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge, vertical: AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppDecorations.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RATING COMPARISON',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          LayoutBuilder(
            builder: (context, constraints) {
              final barW = constraints.maxWidth;
              return Column(
                children: [
                  // Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: SizedBox(
                      height: 9,
                      width: barW,
                      child: Row(
                        children: [
                          Container(
                            width: barW * leftFraction,
                            color: r1 >= r2
                                ? AppColors.primary
                                : AppColors.primary.withOpacity(0.25),
                          ),
                          Expanded(
                            child: Container(
                              color: r2 > r1
                                  ? AppColors.primary
                                  : AppColors.primary.withOpacity(0.25),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        has1 ? r1.toStringAsFixed(1) : 'New',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: r1 >= r2 ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        has2 ? r2.toStringAsFixed(1) : 'New',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: r2 > r1 ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          widget.product1.name,
                          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.product2.name,
                          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Reviews section ──────────────────────────────────────────────────────────

  Widget _buildReviewsSection() {
    if (_loadingReviews) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(child: ReviewCardSkeleton()),
          SizedBox(width: AppSpacing.medium),
          Expanded(child: ReviewCardSkeleton()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: AppColors.border.withOpacity(0.7), thickness: 1)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.large),
              child: Text(
                'REVIEWS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Expanded(child: Divider(color: AppColors.border.withOpacity(0.7), thickness: 1)),
          ],
        ),
        const SizedBox(height: AppSpacing.xLarge),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildReviewColumn(_reviews1, widget.product1)),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
              color: AppColors.border.withOpacity(0.4),
            ),
            Expanded(child: _buildReviewColumn(_reviews2, widget.product2)),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewColumn(List<ReviewDto> reviews, ProductDto product) {
    final list = reviews.take(5).toList();
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.large),
        child: Text(
          'No reviews yet',
          style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: list.map((r) => _buildReviewCard(r, product)).toList(),
    );
  }

  Widget _buildReviewCard(ReviewDto r, ProductDto product) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewDetailPage(review: r, product: product)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.medium),
        padding: const EdgeInsets.all(AppSpacing.large),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppDecorations.softCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + username
            Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    r.ownerUserName.isNotEmpty ? r.ownerUserName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.ownerUserName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Star row
            Row(
              children: List.generate(
                5,
                (i) => Icon(
                  i < r.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 11,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 5),
            // Description
            Text(
              (r.description != null && r.description!.trim().isNotEmpty)
                  ? r.description!
                  : r.title,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── VS badge ────────────────────────────────────────────────────────────────────

class _VsBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'VS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

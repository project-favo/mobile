import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_decorations.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/utils/product_rating_display.dart';
import '../../../../../core/utils/entity_active.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
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

  String? _aiInsight;
  bool _aiLoading = true;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _loadReviews();
    _loadAiInsight();
  }

  Future<void> _loadAiInsight() async {
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    final id1 = int.tryParse(widget.product1.id);
    final id2 = int.tryParse(widget.product2.id);
    if (id1 == null || id2 == null) {
      if (mounted) {
        setState(() {
          _aiLoading = false;
          _aiError = 'Invalid product data.';
        });
      }
      return;
    }

    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        if (mounted) {
          setState(() {
            _aiLoading = false;
            _aiError = 'Sign in to get an AI comparison.';
          });
        }
        return;
      }

      Response<dynamic> response;
      try {
        response = await ApiClient().dio.post(
          '/api/chat/compare',
          data: <String, dynamic>{'productId1': id1, 'productId2': id2},
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          final u = fb.FirebaseAuth.instance.currentUser;
          if (u == null) rethrow;
          final newToken = await u.getIdToken(true);
          if (newToken == null) rethrow;
          ApiClient().setAuthToken(newToken);
          response = await ApiClient().dio.post(
            '/api/chat/compare',
            data: <String, dynamic>{'productId1': id1, 'productId2': id2},
          );
        } else {
          rethrow;
        }
      }

      final data = response.data;
      final replyText = (data is Map && data['reply'] is String)
          ? (data['reply'] as String).trim()
          : null;

      if (!mounted) return;
      setState(() {
        _aiLoading = false;
        if (replyText != null && replyText.isNotEmpty) {
          _aiInsight = replyText;
          _aiError = null;
        } else {
          _aiError = 'No comparison text received.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiLoading = false;
        _aiError = ErrorHandler.getUserFriendlyMessage(e);
        _aiInsight = null;
      });
    }
  }

  Future<void> _loadReviews() async {
    String? token;
    try {
      token = await _sessionHelper.getTokenAndSetHeader();
    } catch (_) {}
    try {
      final results = await Future.wait([
        _reviewRepository
            .getReviewsByProductId(widget.product1.id, firebaseIdToken: token)
            .catchError((_) => <ReviewDto>[]),
        _reviewRepository
            .getReviewsByProductId(widget.product2.id, firebaseIdToken: token)
            .catchError((_) => <ReviewDto>[]),
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

  /// Green border + "Higher rated" only when **both** have scores and one is ahead (no tie).
  /// If one product has no rating, we do not crown the other as "higher" — a 1.8 must not
  /// beat a product with unknown reception.
  int? _ratingWinnerSide() {
    final has1 = productHasMeaningfulRating(widget.product1.averageRating);
    final has2 = productHasMeaningfulRating(widget.product2.averageRating);
    if (!has1 || !has2) return null;
    final r1 = _rating(widget.product1);
    final r2 = _rating(widget.product2);
    if ((r1 - r2).abs() < 0.02) return null;
    return r1 > r2 ? 1 : 2;
  }

  bool _isRatingLeader(int which) => _ratingWinnerSide() == which;

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
            const SizedBox(height: 20),
            _buildAiInsightCard(),
            const SizedBox(height: 20),
            _buildRatingBar(),
            const SizedBox(height: AppSpacing.xxLarge),
            _buildReviewsSection(),
          ],
        ),
      ),
    );
  }

  // ── Product cards with floating VS badge ────────────────────────────────────

  static const double _compareVsGap = 40;

  /// Alt metin alanı (padding + 2 satır isim + etiket + puan + alt rozet/boşluk).
  /// Çok sıkı olursa Flutter 1px overflow (RenderFlex) verebilir; biraz pay bırakıyoruz.
  static const double _compareCardTextBlockHeight = 148.0;

  Widget _buildProductCardsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - _compareVsGap) / 2;
        final cardTotalHeight = cardWidth + _compareCardTextBlockHeight;
        final badgeTop = cardWidth / 2 - 16;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildProductCard(
                    widget.product1,
                    _isRatingLeader(1),
                    cardWidth: cardWidth,
                    cardHeight: cardTotalHeight,
                  ),
                ),
                SizedBox(width: _compareVsGap),
                Expanded(
                  child: _buildProductCard(
                    widget.product2,
                    _isRatingLeader(2),
                    cardWidth: cardWidth,
                    cardHeight: cardTotalHeight,
                  ),
                ),
              ],
            ),
            Positioned(
              top: badgeTop,
              child: _VsBadge(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProductCard(
    ProductDto p,
    bool isRatingLeader, {
    required double cardWidth,
    required double cardHeight,
  }) {
    final rating = _rating(p);
    final hasRating = productHasMeaningfulRating(p.averageRating);

    return GestureDetector(
      onTap: () => Navigator.push(context, SlideRightRoute(page: ReviewPage(product: p))),
      child: Container(
        height: cardHeight,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isRatingLeader
                ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                : AppColors.border.withValues(alpha: 0.35),
            width: isRatingLeader ? 1.5 : 1,
          ),
          boxShadow: AppDecorations.softCardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: cardWidth,
              width: double.infinity,
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.28,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.tag.name.toUpperCase(),
                      style: AppTextStyles.productCategory.copyWith(fontSize: 8.5, letterSpacing: 0.6),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (hasRating)
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '/ 5',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'No rating',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary.withValues(alpha: 0.85),
                        ),
                      ),
                    const Spacer(),
                    if (isRatingLeader && hasRating)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.emoji_events_rounded, size: 12, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Higher rated',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.green.shade800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiInsightCard() {
    if (_aiLoading) {
      return _AiInsightSkeleton();
    }
    if (_aiError != null) {
      return _AiInsightError(
        message: _aiError!,
        onRetry: _loadAiInsight,
      );
    }
    final text = _aiInsight;
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.09),
            AppColors.surface,
            AppColors.primary.withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.16),
        ),
        boxShadow: AppDecorations.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI INSIGHT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Quick comparison',
                      style: AppTextStyles.heading3.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CollapsibleCompareInsightText(
            text: text,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textPrimary,
              height: 1.5,
              fontSize: 14,
            ),
          ),
        ],
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

    final bothRated = has1 && has2;
    final total = r1 + r2;
    final leftFraction = total > 0 ? (r1 / total).clamp(0.05, 0.95) : 0.5;
    final winner = _ratingWinnerSide();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.3),
        ),
        boxShadow: AppDecorations.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'RATING COMPARISON',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.9,
            ),
          ),
          if (!bothRated) ...[
            const SizedBox(height: 10),
            Text(
              'Side-by-side scores need a rating on both products. One has no community score yet — no “winner” here.',
              style: AppTextStyles.bodySecondary.copyWith(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (bothRated)
            LayoutBuilder(
              builder: (context, constraints) {
                final barW = constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.product1.name,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary.withValues(alpha: 0.95),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                r1.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                                  letterSpacing: -0.3,
                                  color: winner == 1 ? AppColors.primary : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                widget.product2.name,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary.withValues(alpha: 0.95),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                r2.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                                  letterSpacing: -0.3,
                                  color: winner == 2 ? AppColors.primary : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: SizedBox(
                        height: 10,
                        width: barW,
                        child: Row(
                          children: [
                            Container(
                              width: barW * leftFraction,
                              color: r1 >= r2
                                  ? AppColors.primary.withValues(alpha: 0.9)
                                  : AppColors.primary.withValues(alpha: 0.2),
                            ),
                            Expanded(
                              child: Container(
                                color: r2 > r1
                                    ? AppColors.primary.withValues(alpha: 0.9)
                                    : AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ratingBarProductLine(
                    name: widget.product1.name,
                    valueLabel: has1 ? '${r1.toStringAsFixed(1)} / 5' : 'No rating yet',
                    emphasize: false,
                  ),
                ),
                const SizedBox(width: AppSpacing.medium),
                Expanded(
                  child: _ratingBarProductLine(
                    name: widget.product2.name,
                    valueLabel: has2 ? '${r2.toStringAsFixed(1)} / 5' : 'No rating yet',
                    emphasize: false,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _ratingBarProductLine({
    required String name,
    required String valueLabel,
    required bool emphasize,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          valueLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: emphasize ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // ── Reviews section ──────────────────────────────────────────────────────────

  Widget _buildReviewsSection() {
    if (_loadingReviews) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _CompactReviewSkeleton()),
          SizedBox(width: AppSpacing.medium),
          Expanded(child: _CompactReviewSkeleton()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: AppColors.border.withValues(alpha: 0.35), thickness: 1)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.large),
              child: Text(
                'REVIEWS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.9,
                ),
              ),
            ),
            Expanded(child: Divider(color: AppColors.border.withValues(alpha: 0.35), thickness: 1)),
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
              color: AppColors.border.withValues(alpha: 0.4),
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
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
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

// ── AI compare insight (collapsible) ───────────────────────────────────────

class _CompareInsightToggleBar extends StatelessWidget {
  const _CompareInsightToggleBar({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: AppColors.border.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 20, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsed max height; longer copy gets a fade and "Show more".
class _CollapsibleCompareInsightText extends StatefulWidget {
  const _CollapsibleCompareInsightText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<_CollapsibleCompareInsightText> createState() => _CollapsibleCompareInsightTextState();
}

class _CollapsibleCompareInsightTextState extends State<_CollapsibleCompareInsightText> {
  static const double _kCollapsedMaxHeight = 200;
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _CollapsibleCompareInsightText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textDir = Directionality.of(context);
        final lineHeight = (widget.style.fontSize ?? 14) * (widget.style.height ?? 1.45);
        final maxLinesCollapsed = (_kCollapsedMaxHeight / lineHeight).floor().clamp(4, 14);

        final tpFull = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: textDir,
        )..layout(maxWidth: constraints.maxWidth);
        final fullH = tpFull.height;
        final needsMore = fullH > _kCollapsedMaxHeight;

        if (!needsMore) {
          return Text(widget.text, style: widget.style);
        }

        if (_expanded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.text, style: widget.style),
              const SizedBox(height: 4),
              _CompareInsightToggleBar(
                label: 'Show less',
                icon: Icons.expand_less_rounded,
                onPressed: () => setState(() => _expanded = false),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Text(
                  widget.text,
                  style: widget.style,
                  maxLines: maxLinesCollapsed,
                  overflow: TextOverflow.clip,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 48,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.primary.withValues(alpha: 0.0),
                            AppColors.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            _CompareInsightToggleBar(
              label: 'Show more',
              icon: Icons.expand_more_rounded,
              onPressed: () => setState(() => _expanded = true),
            ),
          ],
        );
      },
    );
  }
}

// ── AI compare insight ───────────────────────────────────────────────────────

class _AiInsightSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xLarge,
        AppSpacing.large,
        AppSpacing.xLarge,
        AppSpacing.large,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.4),
        ),
        boxShadow: AppDecorations.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonLoader(
                width: 36,
                height: 36,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: AppSpacing.medium),
              const Expanded(
                child: SkeletonLoader(
                  width: 120,
                  height: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.large),
          ...List.generate(
            4,
            (i) => Padding(
              padding: EdgeInsets.only(
                bottom: i == 3 ? 0 : 8,
              ),
              child: SkeletonLoader(
                width: i == 3 ? 180 : double.infinity,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiInsightError extends StatelessWidget {
  const _AiInsightError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xLarge,
        AppSpacing.large,
        AppSpacing.xLarge,
        AppSpacing.large,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.4),
        ),
        boxShadow: AppDecorations.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.small),
              Text(
                'AI insight',
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.medium),
          Text(
            message,
            style: AppTextStyles.bodySecondary.copyWith(
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          TextButton.icon(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Compact skeleton for narrow review columns ────────────────────────────────

class _CompactReviewSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(2, (_) => _singleCard()),
    );
  }

  Widget _singleCard() {
    return Container(
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
          Row(
            children: [
              SkeletonLoader(width: 22, height: 22, borderRadius: BorderRadius.circular(11)),
              const SizedBox(width: 6),
              const Expanded(child: SkeletonLoader(width: double.infinity, height: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(
              5,
              (_) => Padding(
                padding: const EdgeInsets.only(right: 3),
                child: SkeletonLoader(width: 11, height: 11, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const SkeletonLoader(width: double.infinity, height: 11),
          const SizedBox(height: 4),
          const SkeletonLoader(width: double.infinity, height: 11),
          const SizedBox(height: 4),
          const SkeletonLoader(width: double.infinity, height: 11),
        ],
      ),
    );
  }
}

// ── VS badge ────────────────────────────────────────────────────────────────────

class _VsBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'vs',
          style: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.9),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

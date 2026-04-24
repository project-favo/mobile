import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../../../core/theme/app_icon_sizes.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/product_rating_display.dart';
import '../../../../core/widgets/rating_stars_row.dart';
import '../../../../core/utils/entity_active.dart';
import '../../../../core/utils/session_helper.dart';
import '../data/repositories/interaction_repository.dart';
import '../data/repositories/review_repository.dart';
import '../data/models/review_dto.dart';

/// Basit, in-memory review count cache (sadece app çalışırken tutulur).
class _ReviewCountCache {
  static final Map<String, int> _cache = {};

  static int? get(String productId) => _cache[productId];

  static void set(String productId, int count) {
    _cache[productId] = count;
  }

  static void remove(String productId) {
    _cache.remove(productId);
  }
}

class _LikeCountCache {
  static final Map<String, int> _cache = {};

  static int? get(String productId) => _cache[productId];

  static void set(String productId, int count) {
    _cache[productId] = count;
  }

  static void remove(String productId) {
    _cache.remove(productId);
  }
}

class _RatingCache {
  static final Map<String, double> _cache = {};

  static double? get(String productId) => _cache[productId];

  static void set(String productId, double rating) {
    _cache[productId] = rating;
  }

  static void remove(String productId) {
    _cache.remove(productId);
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
  final bool fetchSocialCounts;

  /// Avatar URL'leri — bu ürünü beğenen takip edilen kullanıcılar.
  /// Boş liste ise hiç gösterilmez.
  final List<String> friendAvatarUrls;

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
    this.fetchSocialCounts = true,
    this.friendAvatarUrls = const [],
    this.onTap,
    this.onFavoriteTap,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  int? _reviewCount;
  int? _likeCount;
  double? _resolvedRating;
  static const double _titleBlockHeight = 56;
  static const double _metaRowHeight = 18;

  @override
  void initState() {
    super.initState();
    if (widget.loadReviewCount) {
      _reviewCount = _ReviewCountCache.get(widget.productId);
      _likeCount = _LikeCountCache.get(widget.productId);
      _resolvedRating = _RatingCache.get(widget.productId);
      if (widget.fetchSocialCounts) {
        _loadSocialCounts();
      }
    }
  }

  @override
  void didUpdateWidget(ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.loadReviewCount) {
      if (oldWidget.isFavorite == widget.isFavorite) return;
      final c = _LikeCountCache.get(widget.productId);
      if (c != null) {
        setState(() {
          _likeCount = c;
        });
      }
      return;
    }
    if (!oldWidget.fetchSocialCounts && widget.fetchSocialCounts) {
      _loadSocialCounts();
    }
    // Ana sayfa: [seedProductCardSocialCaches] / parent [setState] sonrası önbellekten oku
    final rc = _ReviewCountCache.get(widget.productId);
    final lc = _LikeCountCache.get(widget.productId);
    final rr = _RatingCache.get(widget.productId);
    var needBuild = false;
    if (rc != null && rc != _reviewCount) {
      _reviewCount = rc;
      needBuild = true;
    }
    if (lc != null && lc != _likeCount) {
      _likeCount = lc;
      needBuild = true;
    }
    if (rr != null && rr != _resolvedRating) {
      _resolvedRating = rr;
      needBuild = true;
    }
    if (oldWidget.isFavorite != widget.isFavorite) {
      final c = _LikeCountCache.get(widget.productId);
      if (c != null) {
        _likeCount = c;
        needBuild = true;
      }
    }
    if (needBuild && mounted) setState(() {});
  }

  Future<void> _loadSocialCounts() async {
    try {
      final reviewRepository = ReviewRepository();
      final interactionRepository = InteractionRepository();
      final token = await SessionHelper().ensureSession();
      final futures = await Future.wait([
        reviewRepository.getReviewsByProductId(
          widget.productId,
          firebaseIdToken: token,
        ),
        interactionRepository.getProductLikeCount(widget.productId),
      ]);
      if (!mounted) return;
      final reviews = filterVisibleReviews(
        futures[0] as List<ReviewDto>,
      );
      final likeCount = futures[1] as int;
      final count = reviews.length;
      final sumRating = reviews.fold<int>(0, (sum, r) => sum + r.rating);
      final computedRating = count > 0 ? (sumRating / count) : 0.0;
      _ReviewCountCache.set(widget.productId, count);
      _LikeCountCache.set(widget.productId, likeCount);
      _RatingCache.set(widget.productId, computedRating);
      setState(() {
        _reviewCount = count;
        _likeCount = likeCount;
        _resolvedRating = computedRating;
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
    // Backend [averageRating] tüm yorumları sayabilir; [filterVisibleReviews] ile gelen
    // yorum yoksa kartta puan + baloncuğu da gösterme (askıdaki yorum yıldızı kalmasın).
    final int? visibleReviewCount = widget.loadReviewCount ? _reviewCount : null;
    final bool noVisibleReviews = visibleReviewCount != null && visibleReviewCount == 0;
    final bool showFriendBubbles = widget.friendAvatarUrls.isNotEmpty && !noVisibleReviews;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenW = MediaQuery.sizeOf(context).width;
    // 2 sütunlu grid: her kart (screenW - 2×16 dış padding - 16 ara boşluk) / 2
    // Görseller 800×800 kare → cache de kare olsun, bozulma olmasın
    final cardPx = ((screenW - 48) / 2 * dpr).round().clamp(150, 600);
    final imageCacheW = cardPx;
    final imageCacheH = cardPx;

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
                child: Stack(
                  children: [
                    Positioned.fill(
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
                            fit: BoxFit.cover,
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
                    if (showFriendBubbles)
                      Positioned(
                        left: 7,
                        bottom: 7,
                        child: _FriendAvatarStack(
                          avatarUrls: widget.friendAvatarUrls,
                        ),
                      ),
                  ],
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
                  style: AppTextStyles.productTitle.copyWith(
                    fontSize: 14.5,
                    height: 1.2,
                  ),
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
                  if (noVisibleReviews) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No rating yet',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  final raw = _resolvedRating ?? widget.rating;
                  if (!productHasMeaningfulRating(raw)) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No rating yet',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  final rating = (raw.isNaN || raw.isInfinite)
                      ? 0.0
                      : raw.clamp(0.0, 5.0);
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: RatingStarsRow(
                      rating: rating,
                      size: 12.5,
                      gap: 1.5,
                      showNumeric: true,
                    ),
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
                    Expanded(
                      child: Text(
                        '${_reviewCount ?? 0} ${(_reviewCount ?? 0) == 1 ? 'review' : 'reviews'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
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

// ─── Friend avatar stack overlay ─────────────────────────────────────────────

class _FriendAvatarStack extends StatelessWidget {
  final List<String> avatarUrls;

  const _FriendAvatarStack({required this.avatarUrls});

  @override
  Widget build(BuildContext context) {
    const double size = 22;
    const double step = 15;
    const double border = 1.8;

    final shown = avatarUrls.take(5).toList();
    final extra = avatarUrls.length - shown.length;
    final itemCount = shown.length + (extra > 0 ? 1 : 0);
    final stackWidth = step * (itemCount - 1) + size;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        height: size,
        width: stackWidth,
        child: Stack(
          children: [
            ...List.generate(shown.length, (i) {
              final parsed = _AvatarPayload.parse(shown[i]);
              return Positioned(
                left: i * step,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: border),
                  ),
                  child: ClipOval(
                    child: ProfileAvatar(
                      key: ValueKey('friend_avatar_$i/${parsed.key}'),
                      radius: (size - border * 2) / 2,
                      imageUrl: parsed.imageUrl,
                      fallbackInitial: parsed.fallbackInitial,
                    ),
                  ),
                ),
              );
            }),
            if (extra > 0)
              Positioned(
                left: shown.length * step,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: border),
                    color: AppColors.primary,
                  ),
                  child: Center(
                    child: Text(
                      '+$extra',
                      style: const TextStyle(
                        fontSize: 7,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPayload {
  final String key;
  final String? imageUrl;
  final String fallbackInitial;

  const _AvatarPayload({
    required this.key,
    required this.imageUrl,
    required this.fallbackInitial,
  });

  static _AvatarPayload parse(String raw) {
    if (raw.startsWith('url:')) {
      final url = raw.substring(4).trim();
      return _AvatarPayload(
        key: raw,
        imageUrl: url.isEmpty ? null : url,
        fallbackInitial: '?',
      );
    }
    if (raw.startsWith('fallback:')) {
      final parts = raw.split(':');
      final initial = parts.length >= 3 && parts[2].trim().isNotEmpty
          ? parts[2].trim()[0].toUpperCase()
          : '?';
      return _AvatarPayload(
        key: raw,
        imageUrl: null,
        fallbackInitial: initial,
      );
    }
    // Legacy payload: direct URL string.
    final legacy = raw.trim();
    return _AvatarPayload(
      key: raw,
      imageUrl: legacy.isEmpty ? null : legacy,
      fallbackInitial: '?',
    );
  }
}

/// Call when like/review counts may have changed off-card (e.g. from [ReviewPage]).
void invalidateProductCardSocialCaches(String productId) {
  if (productId.isEmpty) return;
  _ReviewCountCache.remove(productId);
  _LikeCountCache.remove(productId);
  _RatingCache.remove(productId);
}

/// Detay ekranından dönmeden hemen (sunucu refetch yok) grid sayılarını doldurur; flash yapmaz.
void seedProductCardSocialCaches(
  String productId, {
  required int likeCount,
  required int reviewCount,
  double? rating,
}) {
  if (productId.isEmpty) return;
  _LikeCountCache.set(productId, likeCount);
  _ReviewCountCache.set(productId, reviewCount);
  if (rating != null) {
    _RatingCache.set(productId, rating);
  }
}

/// Sunucudan gelen sayaçlarla in-memory cache’i günceller; kartı söküp [invalidate] etmez
/// (böylece eski değer → 0/loading anı olmaz).
void setProductCardSocialCaches(
  String productId, {
  required int likeCount,
  required int reviewCount,
  double? rating,
}) {
  if (productId.isEmpty) return;
  _LikeCountCache.set(productId, likeCount);
  _ReviewCountCache.set(productId, reviewCount);
  if (rating != null) {
    _RatingCache.set(productId, rating);
  }
}

/// Ana sayfa grid’de like toggler; in-memory like sayacını [seed] değerinin üstüne tekrar +1 eklemesin.
void applyLocalLikeCountDeltaOnToggle(
  String productId, {
  required bool wasLiked,
  required bool isNowLiked,
}) {
  if (productId.isEmpty) return;
  if (wasLiked == isNowLiked) return;
  final cur = _LikeCountCache.get(productId) ?? 0;
  final next = (cur + (isNowLiked ? 1 : -1)).clamp(0, 999999);
  _LikeCountCache.set(productId, next);
}

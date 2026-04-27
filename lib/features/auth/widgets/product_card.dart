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

  static void clearAll() => _cache.clear();
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

  static void clearAll() => _cache.clear();
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

  static void clearAll() => _cache.clear();
}

class _PhotoReviewCache {
  static final Map<String, bool> _cache = {};

  static bool? get(String productId) => _cache[productId];

  static void set(String productId, bool hasPhoto) {
    _cache[productId] = hasPhoto;
  }

  static void remove(String productId) {
    _cache.remove(productId);
  }

  static void clearAll() => _cache.clear();
}

/// Grid’de kalp [isLiked] zenginleştirmeden gelirken like sayısı ayrı uç/önbellekten 0 gelebiliyor.
/// Wishlist’te olduğumuz halde toplam like en az 1 olmalı.
int reconcileLikeCountWithWishlist({
  required bool isWishlisted,
  required int serverCount,
}) {
  if (isWishlisted && serverCount < 1) return 1;
  return serverCount;
}

/// [getProductLikeCount] yanıtı optimistic toggle’dan sonra gelebilir; tek adımlık gecikmeyi düzelt.
int mergeLikeCountWithRecentCache({
  required bool isWishlisted,
  required int serverCount,
  int? cachedLikeNow,
}) {
  final v = reconcileLikeCountWithWishlist(
    isWishlisted: isWishlisted,
    serverCount: serverCount,
  );
  final prev = cachedLikeNow;
  if (prev == null) return v;
  if (isWishlisted && v + 1 == prev) return prev;
  if (!isWishlisted && v == prev + 1) return prev;
  return v;
}

/// Görünür yorumlarda en az bir foto / ek medya var mı (ProductCard grid).
bool _visibleReviewsIncludePhoto(ReviewDto r) {
  if (r.mediaList.isEmpty) return false;
  for (final m in r.mediaList) {
    if (m.id.isNotEmpty) return true;
    final u = (m.url ?? m.imageUrl)?.trim() ?? '';
    if (u.isNotEmpty) return true;
  }
  return false;
}

/// [seedProductCardSocialCaches] / ebeveyn yenilemeleri için dışa açık kontrol.
bool anyVisibleReviewHasPhoto(Iterable<ReviewDto> reviews) {
  return reviews.any(_visibleReviewsIncludePhoto);
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

  /// Arkadaş feed’inden gelen avatarlar (sadece takip edilen + review bırakan kişiler).
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
  bool? _hasPhotoReview;
  static const double _titleBlockHeight = 56;
  static const double _metaRowHeight = 18;

  @override
  void initState() {
    super.initState();
    if (widget.loadReviewCount) {
      _reviewCount = _ReviewCountCache.get(widget.productId);
      final lcRaw = _LikeCountCache.get(widget.productId);
      if (lcRaw != null) {
        final adj = reconcileLikeCountWithWishlist(
          isWishlisted: widget.isFavorite,
          serverCount: lcRaw,
        );
        _likeCount = adj;
        if (adj != lcRaw) {
          _LikeCountCache.set(widget.productId, adj);
        }
      }
      _resolvedRating = _RatingCache.get(widget.productId);
      _hasPhotoReview = _PhotoReviewCache.get(widget.productId);
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
        final adj = reconcileLikeCountWithWishlist(
          isWishlisted: widget.isFavorite,
          serverCount: c,
        );
        if (adj != c) _LikeCountCache.set(widget.productId, adj);
        setState(() {
          _likeCount = adj;
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
    final ph = _PhotoReviewCache.get(widget.productId);
    var needBuild = false;
    if (rc != null && rc != _reviewCount) {
      _reviewCount = rc;
      needBuild = true;
    }
    if (lc != null) {
      final adj = reconcileLikeCountWithWishlist(
        isWishlisted: widget.isFavorite,
        serverCount: lc,
      );
      if (adj != lc) _LikeCountCache.set(widget.productId, adj);
      if (adj != _likeCount) {
        _likeCount = adj;
        needBuild = true;
      }
    }
    if (rr != null && rr != _resolvedRating) {
      _resolvedRating = rr;
      needBuild = true;
    }
    if (ph != null && ph != _hasPhotoReview) {
      _hasPhotoReview = ph;
      needBuild = true;
    }
    if (oldWidget.isFavorite != widget.isFavorite) {
      final c = _LikeCountCache.get(widget.productId);
      if (c != null) {
        final adj = reconcileLikeCountWithWishlist(
          isWishlisted: widget.isFavorite,
          serverCount: c,
        );
        if (adj != c) _LikeCountCache.set(widget.productId, adj);
        if (adj != _likeCount) {
          _likeCount = adj;
          needBuild = true;
        }
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
      final likeCount = mergeLikeCountWithRecentCache(
        isWishlisted: widget.isFavorite,
        serverCount: futures[1] as int,
        cachedLikeNow: _LikeCountCache.get(widget.productId),
      );
      final count = reviews.length;
      final sumRating = reviews.fold<int>(0, (sum, r) => sum + r.rating);
      final computedRating = count > 0 ? (sumRating / count) : 0.0;
      final hasPhoto = reviews.any(_visibleReviewsIncludePhoto);
      _ReviewCountCache.set(widget.productId, count);
      _LikeCountCache.set(widget.productId, likeCount);
      _RatingCache.set(widget.productId, computedRating);
      _PhotoReviewCache.set(widget.productId, hasPhoto);
      setState(() {
        _reviewCount = count;
        _likeCount = likeCount;
        _resolvedRating = computedRating;
        _hasPhotoReview = hasPhoto;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reviewCount ??= 0;
        _likeCount = reconcileLikeCountWithWishlist(
          isWishlisted: widget.isFavorite,
          serverCount: _likeCount ?? 0,
        );
        _hasPhotoReview ??= false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Backend [averageRating] tüm yorumları sayabilir; [filterVisibleReviews] ile gelen
    // yorum yoksa kartta puan + baloncuğu da gösterme (askıdaki yorum yıldızı kalmasın).
    final int? visibleReviewCount = widget.loadReviewCount ? _reviewCount : null;
    final bool noVisibleReviews = visibleReviewCount != null && visibleReviewCount == 0;
    // Baloncuklar sadece takip edilen + review bırakan kullanıcılar için (Home'dan friendAvatarUrls).
    final displayBubbleKeys = widget.friendAvatarUrls;
    final bool showAvatarBubbles = displayBubbleKeys.isNotEmpty;

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
                    if (showAvatarBubbles)
                      Positioned(
                        left: 7,
                        bottom: 7,
                        child: _FriendAvatarStack(
                          avatarUrls: displayBubbleKeys,
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
                  final showPhotoBadge =
                      widget.loadReviewCount &&
                      _hasPhotoReview == true &&
                      !noVisibleReviews;
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'No rating yet',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (showPhotoBadge) _buildPhotoReviewBadge(leadingGap: 6),
                        ],
                      ),
                    );
                  }
                  final rating = (raw.isNaN || raw.isInfinite)
                      ? 0.0
                      : raw.clamp(0.0, 5.0);
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        RatingStarsRow(
                          rating: rating,
                          size: 12.5,
                          gap: 1.5,
                          showNumeric: true,
                        ),
                        if (showPhotoBadge) _buildPhotoReviewBadge(leadingGap: 4),
                      ],
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

  /// Trendyol/Amazon tarzı: fotoğraflı yorum varsa ratingin hemen sağında minimal kamera.
  Widget _buildPhotoReviewBadge({double leadingGap = 4}) {
    return Semantics(
      label: 'Includes photo reviews',
      child: Padding(
        padding: EdgeInsets.only(left: leadingGap),
        child: Icon(
          Icons.photo_camera_outlined,
          size: 13.5,
          color: AppColors.textSecondary.withValues(alpha: 0.88),
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
  _PhotoReviewCache.remove(productId);
}

/// [clearAllAppCachesOnLogout] — hesap değişiminde eski yorum/like sayıları kalmesin.
void clearAllProductCardSocialCaches() {
  _ReviewCountCache.clearAll();
  _LikeCountCache.clearAll();
  _RatingCache.clearAll();
  _PhotoReviewCache.clearAll();
}

final List<void Function(String productId)> _productCardGridResyncHandlers = [];

void registerProductCardGridResyncHandler(void Function(String productId) onProductId) {
  _productCardGridResyncHandlers.add(onProductId);
}

void unregisterProductCardGridResyncHandler(void Function(String productId) onProductId) {
  _productCardGridResyncHandlers.remove(onProductId);
}

/// Profil "My reviews" yorum silme gibi: ana sayfa/arama [ProductCard] anında sunucuyla hizalansın.
void notifyProductCardGridResyncNeeded(String productId) {
  if (productId.isEmpty) return;
  for (final h in List<void Function(String)>.from(_productCardGridResyncHandlers)) {
    h(productId);
  }
}

/// Detay ekranından dönmeden hemen (sunucu refetch yok) grid sayılarını doldurur; flash yapmaz.
void seedProductCardSocialCaches(
  String productId, {
  required int likeCount,
  required int reviewCount,
  double? rating,
  bool? hasPhotoReview,
}) {
  if (productId.isEmpty) return;
  _LikeCountCache.set(productId, likeCount);
  _ReviewCountCache.set(productId, reviewCount);
  if (rating != null) {
    _RatingCache.set(productId, rating);
  }
  if (hasPhotoReview != null) {
    _PhotoReviewCache.set(productId, hasPhotoReview);
  }
}

/// Sunucudan gelen sayaçlarla in-memory cache’i günceller; kartı söküp [invalidate] etmez
/// (böylece eski değer → 0/loading anı olmaz).
void setProductCardSocialCaches(
  String productId, {
  required int likeCount,
  required int reviewCount,
  double? rating,
  bool? hasPhotoReview,
}) {
  if (productId.isEmpty) return;
  _LikeCountCache.set(productId, likeCount);
  _ReviewCountCache.set(productId, reviewCount);
  if (rating != null) {
    _RatingCache.set(productId, rating);
  }
  if (hasPhotoReview != null) {
    _PhotoReviewCache.set(productId, hasPhotoReview);
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

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/review_card.dart';
import '../widgets/report_review_sheet.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/custom_refresh_indicator.dart';
import '../../../../../core/widgets/custom_snack_bar.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/exceptions.dart';
import '../../../../../core/utils/product_rating_display.dart';
import '../../../../../core/utils/app_datetime.dart';
import '../../../../../core/cache/current_user_cache.dart';
import '../../../../../core/cache/self_review_like_local_prefs.dart';
import '../../../../../core/cache/product_memory_cache.dart';
import '../../../../../core/cache/review_memory_cache.dart';
import '../../../../../core/utils/in_flight_id_lock.dart';
import '../../../../../core/utils/review_report_storage.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/utils/content_availability_messages.dart';
import '../../../../../core/utils/content_unavailable_dialog.dart';
import '../../../../../core/config/app_background_timers.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../../../core/utils/entity_active.dart';
import '../../../../../core/utils/user_profile_navigation.dart';
import '../../../data/models/notification_dto.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/tag_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/message_repository.dart';
import '../../../data/services/auth_service.dart';
import 'add_review_page.dart';
import 'review_detail_page.dart';
import 'compare_product_select_page.dart';
import '../../messages/product_ai_chat_page.dart';
import '../review_page_pop_result.dart';
import '../widgets/review_delete_flow.dart';
import '../../home_page.dart';
import '../../../../../core/notifications/notification_realtime_service.dart';

class ReviewPage extends StatefulWidget {
  /// Tam product verilirse doğrudan kullanılır.
  /// Sadece [productId] (ve isteğe bağlı [productName]) verilirse sayfa hemen açılır, ürün arka planda yüklenir.
  final ProductDto? product;
  final String? productId;
  final String? productName;

  const ReviewPage({super.key, this.product, this.productId, this.productName});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> with WidgetsBindingObserver {
  final InteractionRepository _interactionRepository = InteractionRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  final ProductRepository _productRepository = ProductRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final MessageRepository _messageRepository = MessageRepository();
  String? _currentUsername;
  String? _currentUserId;
  late ProductDto _currentProduct;
  bool _isLoadingProduct =
      false; // productId ile açıldıysa ürün yüklenene kadar
  List<ReviewDto> _reviews = [];
  bool _isLoadingReviews = true;
  String? _errorMessage;
  int _likeCount = 0;
  Map<int, int>? _cachedRatingCounts;
  bool _isRatingExpanded = false;
  bool _isDescriptionExpanded = false;
  final InFlightFlag _productPageLikeLock = InFlightFlag();
  bool _isProductLikeMutationInFlight = false;
  bool _queuedProductLikeToggleParity = false;
  bool? _productLikeUiOverride;
  int _likeCountFetchSeq = 0;
  int _productLikeStatusFetchSeq = 0;
  final InFlightIdLock _reviewListLikeLock = InFlightIdLock();
  final InFlightIdLock _reviewDeleteLock = InFlightIdLock();
  static const Duration _productListingPollInterval =
      AppBackgroundTimers.standardListPoll;
  Timer? _productListingPollTimer;
  bool _poppedBecauseProductUnlisted = false;
  /// [_syncProductPageInBackground] tekil çalışsın; üst üste API çağrısı olmasın.
  bool _pageBackgroundSyncInFlight = false;
  StreamSubscription<NotificationPushEvent>? _reviewDeactivatedSub;
  final Map<String, List<ReviewDto>> _reviewQueryCache = {};
  final Map<String, DateTime> _reviewQueryCacheTimes = {};
  static const Duration _reviewQueryCacheTtl = Duration(seconds: 25);
  /// GET /users/{id} — review JSON’unda askı yoksa bile vitrin dışı yazarları ele.
  final Map<String, ({bool blocked, DateTime checkedAt})> _ownerGateById = {};
  static const Duration _ownerGateRecheckTtl = Duration(seconds: 12);
  /// Backend kendi yorumunu beğenmeyi reddederse [SelfReviewLikeLocalPrefs] ile gösterim.
  Map<String, bool> _selfLikeBoostByReviewId = {};
  /// Review detail ile aynı: home ilk 50 dışı + önceki tur vitrin = askı sinyali.
  bool? _lastProductOnHomeFirstPage;
  static const EdgeInsets _contentHorizontalPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xxLarge,
  );
  static const String _sortNewest = ReviewRepository.reviewSortNewest;
  static const String _sortMostLiked = ReviewRepository.reviewSortMostLiked;
  static const String _sortTopFollowerAuthor =
      ReviewRepository.reviewSortTopFollowerAuthor;
  static const String _sortRatingHigh =
      ReviewRepository.reviewSortHighestRating;
  static const String _sortRatingLow = ReviewRepository.reviewSortLowestRating;
  static const String _guestReviewsLoginMessage = 'Please login to view reviews';

  bool? _hasMediaFilter;
  bool? _isCollaborativeFilter;
  String _selectedSort = _sortNewest;

  String _formatReviewRelativeDate(String raw) {
    final parsed = parseBackendDateTimeToLocal(raw);
    if (parsed == null) return '';
    final now = DateTime.now();
    var diff = now.difference(parsed);
    if (diff.isNegative) diff = Duration.zero;
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) {
      final m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 1) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 30) {
      final d = diff.inDays;
      return '$d day${d == 1 ? '' : 's'} ago';
    }
    final month = (diff.inDays / 30).floor();
    if (month < 12) return '$month month${month == 1 ? '' : 's'} ago';
    final year = (diff.inDays / 365).floor();
    return '$year year${year == 1 ? '' : 's'} ago';
  }

  Map<int, int> _ratingCounts() {
    return _cachedRatingCounts ??= _computeRatingCounts();
  }

  Map<int, int> _computeRatingCounts() {
    final counts = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final review in _reviews) {
      final r = review.rating.clamp(1, 5);
      counts[r] = (counts[r] ?? 0) + 1;
    }
    return counts;
  }

  bool get _isUsingDefaultReviewQuery =>
      _hasMediaFilter == null &&
      _isCollaborativeFilter == null &&
      _selectedSort == _sortNewest;
  bool get _hasBinaryReviewFilters =>
      _hasMediaFilter != null || _isCollaborativeFilter != null;

  Future<void> _setSortFilter(String value) async {
    if (_selectedSort == value) return;
    setState(() {
      _selectedSort = value;
    });
    await _loadReviews();
  }

  int get _activeFilterCount =>
      (_hasMediaFilter != null ? 1 : 0) +
      (_isCollaborativeFilter != null ? 1 : 0);

  String _reviewQueryCacheKey() {
    final media = _hasMediaFilter == null
        ? 'all'
        : (_hasMediaFilter! ? 'with_media' : 'without_media');
    final sponsor = _isCollaborativeFilter == null
        ? 'all'
        : (_isCollaborativeFilter! ? 'sponsored' : 'non_sponsored');
    return '${_currentProduct.id}|$_selectedSort|$media|$sponsor';
  }

  List<ReviewDto>? _peekFreshReviewQueryCache() {
    final key = _reviewQueryCacheKey();
    final cachedAt = _reviewQueryCacheTimes[key];
    final cached = _reviewQueryCache[key];
    if (cachedAt == null || cached == null) return null;
    final fresh = DateTime.now().difference(cachedAt) <= _reviewQueryCacheTtl;
    if (!fresh) return null;
    return filterVisibleReviews(cached);
  }

  void _clearLocalReviewQueryCacheForCurrentProduct() {
    final id = _currentProduct.id.trim();
    if (id.isEmpty) return;
    final prefix = '$id|';
    _reviewQueryCache.removeWhere((k, _) => k.startsWith(prefix));
    _reviewQueryCacheTimes.removeWhere((k, _) => k.startsWith(prefix));
  }

  double _averageRatingFromReviews(List<ReviewDto> list) {
    if (list.isEmpty) return 0.0;
    final sum = list.fold<int>(0, (s, r) => s + r.rating);
    return sum / list.length;
  }

  Future<List<ReviewDto>> _filterReviewsHidingBlockedOwners(
    List<ReviewDto> reviews, {
    bool forceRefreshBlockedCache = false,
  }) async {
    final fb = FirebaseAuth.instance.currentUser;
    if (fb == null) return reviews;
    final me = _currentUserId?.trim() ?? '';
    final ownerIds = reviews
        .map((r) => r.ownerId.trim())
        .where((id) => id.isNotEmpty && id != me)
        .toSet()
        .toList();
    if (ownerIds.isEmpty) return reviews;
    if (forceRefreshBlockedCache) {
      for (final oid in ownerIds) {
        _ownerGateById.remove(oid);
      }
    }
    final auth = AuthService();
    Future<void> resolveOne(String ownerId) async {
      final existing = _ownerGateById[ownerId];
      if (!forceRefreshBlockedCache && existing != null) {
        if (existing.blocked) return;
        if (DateTime.now().difference(existing.checkedAt) < _ownerGateRecheckTtl) {
          return;
        }
      }
      try {
        final u = await auth.getUserById(ownerId);
        final blocked = u?.isProfileViewBlocked ?? false;
        _ownerGateById[ownerId] = (blocked: blocked, checkedAt: DateTime.now());
      } on TargetUserNotAvailableException {
        _ownerGateById[ownerId] = (blocked: true, checkedAt: DateTime.now());
      } catch (_) {
        _ownerGateById[ownerId] = (blocked: false, checkedAt: DateTime.now());
      }
    }
    const batch = 6;
    for (var i = 0; i < ownerIds.length; i += batch) {
      final chunk = ownerIds.skip(i).take(batch).toList();
      await Future.wait(chunk.map(resolveOne));
    }
    return reviews
        .where((r) {
          final oid = r.ownerId.trim();
          if (oid.isEmpty || oid == me) return true;
          final g = _ownerGateById[oid];
          if (g == null) return true;
          return !g.blocked;
        })
        .toList();
  }

  void _rememberReviewQueryCache(List<ReviewDto> reviews) {
    final key = _reviewQueryCacheKey();
    _reviewQueryCache[key] = List<ReviewDto>.from(reviews);
    _reviewQueryCacheTimes[key] = DateTime.now();
  }

  String _emptyReviewsMessage() {
    if (_activeFilterCount == 0) {
      return 'No reviews yet. Be the first to review!';
    }

    String mediaText;
    if (_hasMediaFilter == true) {
      mediaText = 'with media';
    } else if (_hasMediaFilter == false) {
      mediaText = 'without media';
    } else {
      mediaText = 'any media type';
    }

    String sponsorText;
    if (_isCollaborativeFilter == true) {
      sponsorText = 'sponsored';
    } else if (_isCollaborativeFilter == false) {
      sponsorText = 'non-sponsored';
    } else {
      sponsorText = 'any sponsorship type';
    }

    if (_hasMediaFilter != null && _isCollaborativeFilter != null) {
      return 'No $sponsorText reviews found $mediaText for this product.';
    }
    if (_hasMediaFilter != null) {
      return 'No reviews found $mediaText for this product.';
    }
    return 'No $sponsorText reviews found for this product.';
  }

  Widget _buildControlIconButton({
    required IconData icon,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : AppColors.border.withValues(alpha: 0.85),
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSortSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (ctx) {
        String tempSort = _selectedSort;
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Text('Sort Reviews', style: AppTextStyles.heading3),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          title: const Text('Newest'),
                          trailing: tempSort == _sortNewest
                              ? const Icon(Icons.check_rounded, color: AppColors.primary)
                              : null,
                          onTap: () => setSheetState(() => tempSort = _sortNewest),
                        ),
                        ListTile(
                          title: const Text('Most liked'),
                          trailing: tempSort == _sortMostLiked
                              ? const Icon(Icons.check_rounded, color: AppColors.primary)
                              : null,
                          onTap: () => setSheetState(() => tempSort = _sortMostLiked),
                        ),
                        ListTile(
                          title: const Text('Top follower author'),
                          trailing: tempSort == _sortTopFollowerAuthor
                              ? const Icon(Icons.check_rounded, color: AppColors.primary)
                              : null,
                          onTap: () => setSheetState(() => tempSort = _sortTopFollowerAuthor),
                        ),
                        ListTile(
                          title: const Text('Highest rating'),
                          trailing: tempSort == _sortRatingHigh
                              ? const Icon(Icons.check_rounded, color: AppColors.primary)
                              : null,
                          onTap: () => setSheetState(() => tempSort = _sortRatingHigh),
                        ),
                        ListTile(
                          title: const Text('Lowest rating'),
                          trailing: tempSort == _sortRatingLow
                              ? const Icon(Icons.check_rounded, color: AppColors.primary)
                              : null,
                          onTap: () => setSheetState(() => tempSort = _sortRatingLow),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xLarge,
                      AppSpacing.small,
                      AppSpacing.xLarge,
                      AppSpacing.large,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
                      ),
                    ),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => setSheetState(() => tempSort = _sortNewest),
                          child: const Text('Reset'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(tempSort),
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await _setSortFilter(selected);
    }
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<Map<String, bool?>>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (ctx) {
        bool? media = _hasMediaFilter;
        bool? sponsored = _isCollaborativeFilter;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget optionRow({
              required String title,
              required bool? value,
              required bool? selected,
              required ValueChanged<bool?> onChanged,
            }) {
              return ListTile(
                dense: true,
                title: Text(title),
                trailing: selected == value
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  setModalState(() => onChanged(value));
                },
              );
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.84,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Center(child: Text('Filter Reviews', style: AppTextStyles.heading3)),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xLarge,
                        vertical: AppSpacing.small,
                      ),
                      child: Text('Media', style: AppTextStyles.bodyBold),
                    ),
                    optionRow(
                      title: 'All',
                      value: null,
                      selected: media,
                      onChanged: (v) => media = v,
                    ),
                    optionRow(
                      title: 'With media',
                      value: true,
                      selected: media,
                      onChanged: (v) => media = v,
                    ),
                    optionRow(
                      title: 'Without media',
                      value: false,
                      selected: media,
                      onChanged: (v) => media = v,
                    ),
                    const Divider(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xLarge,
                        vertical: AppSpacing.small,
                      ),
                      child: Text('Sponsorship', style: AppTextStyles.bodyBold),
                    ),
                    optionRow(
                      title: 'All',
                      value: null,
                      selected: sponsored,
                      onChanged: (v) => sponsored = v,
                    ),
                    optionRow(
                      title: 'Sponsored',
                      value: true,
                      selected: sponsored,
                      onChanged: (v) => sponsored = v,
                    ),
                    optionRow(
                      title: 'Non-sponsored',
                      value: false,
                      selected: sponsored,
                      onChanged: (v) => sponsored = v,
                    ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xLarge,
                        AppSpacing.medium,
                        AppSpacing.xLarge,
                        AppSpacing.large,
                      ),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(ctx).pop(<String, bool?>{
                                'hasMedia': null,
                                'isCollaborative': null,
                              });
                            },
                            child: const Text('Reset'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () {
                              Navigator.of(ctx).pop(<String, bool?>{
                                'hasMedia': media,
                                'isCollaborative': sponsored,
                              });
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return;
    final nextMedia = result['hasMedia'];
    final nextSponsored = result['isCollaborative'];
    if (_hasMediaFilter == nextMedia &&
        _isCollaborativeFilter == nextSponsored) {
      return;
    }
    setState(() {
      _hasMediaFilter = nextMedia;
      _isCollaborativeFilter = nextSponsored;
    });
    await _loadReviews();
  }

  List<String> _productTagHierarchy() {
    final path = (_currentProduct.tag.categoryPath ?? '').trim();
    final fromPath =
        path
            .split(RegExp(r'[>/.]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    final fallbackTag = _currentProduct.tag.name.trim();
    final tags = <String>[];
    for (final t in fromPath) {
      if (!tags.any((e) => e.toLowerCase() == t.toLowerCase())) {
        tags.add(t);
      }
    }
    if (fallbackTag.isNotEmpty &&
        !tags.any((e) => e.toLowerCase() == fallbackTag.toLowerCase())) {
      tags.add(fallbackTag);
    }
    return tags.map(_formatCategoryLabel).toList();
  }

  String _formatCategoryLabel(String raw) {
    final cleaned = raw.trim().replaceAll('_', ' ').replaceAll('-', ' ');
    if (cleaned.isEmpty) return raw;
    return cleaned
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// E-ticaret tarzı minimal kategori yolu (Trendyol / Amazon breadcrumb hissi).
  Widget _buildProductCategoryBreadcrumb() {
    final segments = _productTagHierarchy();
    if (segments.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: 'Category: ${segments.join(' → ')}',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.hint.withValues(alpha: 0.9),
                ),
              ),
            ],
            Text(
              segments[i],
              style: AppTextStyles.bodySmall.copyWith(
                color: i == segments.length - 1
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight:
                    i == segments.length - 1 ? FontWeight.w600 : FontWeight.w500,
                fontSize: 12.5,
                height: 1.2,
                letterSpacing: 0.01,
              ),
            ),
          ],
        ],
        ),
      ),
    );
  }

  bool _shouldShowDescriptionToggle({
    required String text,
    required TextStyle style,
    required double maxWidth,
  }) {
    if (text.trim().isEmpty) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  Widget _buildRatingDistribution() {
    if (_reviews.isEmpty) return const SizedBox.shrink();
    final counts = _ratingCounts();
    final total = _reviews.length;
    return Column(
      children: [5, 4, 3, 2, 1].map((star) {
        final count = counts[star] ?? 0;
        final ratio = total == 0 ? 0.0 : count / total;
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  '$star',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.star_border,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: ratio,
                    backgroundColor: AppColors.border.withValues(alpha: 0.45),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 14,
                child: Text(
                  '$count',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  bool _isMyReview(ReviewDto review) {
    if (CurrentUserCache.instance.isMyReview(review)) return true;
    final id = _currentUserId;
    if (id == null || id.trim().isEmpty) return false;
    return review.ownerId.trim() == id.trim();
  }

  /// Mevcut kullanıcının bu ürüne ait aktif review'u (varsa).
  ReviewDto? get _myReview {
    final id = _currentUserId;
    final cacheOk = CurrentUserCache.instance.hasUserId;
    if ((id == null || id.trim().isEmpty) && !cacheOk) return null;
    try {
      return _reviews.firstWhere((r) => _isMyReview(r));
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncSelfLikeBoostFromPrefsAndServer() async {
    final uid =
        _currentUserId?.trim() ?? CurrentUserCache.instance.userId?.trim() ?? '';
    if (uid.isEmpty) {
      if (mounted) setState(() => _selfLikeBoostByReviewId = {});
      return;
    }
    final disk = await SelfReviewLikeLocalPrefs.instance.loadBoostMap(uid);
    final next = <String, bool>{};
    for (final e in disk.entries) {
      if (e.value != true) continue;
      final rid = e.key;
      ReviewDto? row;
      for (final r in _reviews) {
        if (r.id == rid) {
          row = r;
          break;
        }
      }
      if (row != null && _isMyReview(row)) {
        if (row.isLikedByCurrentUser) {
          await SelfReviewLikeLocalPrefs.instance.setBoost(uid, rid, false);
          continue;
        }
        next[rid] = true;
      }
    }
    if (!mounted) return;
    setState(() => _selfLikeBoostByReviewId = next);
  }

  /// Liste cevabında likeCount gecikmeli / eksik geliyorsa kısa paralel GET ile doldurur.
  Future<void> _hydrateReviewRowLikeCounts() async {
    if (_reviews.isEmpty || !mounted) return;
    const cap = 36;
    const concurrency = 12;
    final slice = _reviews.take(cap).toList();
    final updates = <String, int>{};
    for (var i = 0; i < slice.length; i += concurrency) {
      final part = slice.skip(i).take(concurrency).toList();
      await Future.wait(
        part.map((r) async {
          try {
            updates[r.id] = await _interactionRepository.getReviewLikeCount(
              r.id,
            );
          } catch (_) {}
        }),
      );
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() {
      var changed = false;
      for (var j = 0; j < _reviews.length; j++) {
        final id = _reviews[j].id;
        final c = updates[id];
        if (c == null) continue;
        if (_reviews[j].likeCount == c) continue;
        changed = true;
        final o = _reviews[j];
        _reviews[j] = ReviewDto(
          id: o.id,
          title: o.title,
          description: o.description,
          isCollaborative: o.isCollaborative,
          rating: o.rating,
          createdAt: o.createdAt,
          productId: o.productId,
          productName: o.productName,
          ownerId: o.ownerId,
          ownerUserName: o.ownerUserName,
          ownerProfilePhotoUrl: o.ownerProfilePhotoUrl,
          mediaList: o.mediaList,
          likeCount: c,
          isLikedByCurrentUser: o.isLikedByCurrentUser,
          isProductNotListed: o.isProductNotListed,
          isReviewInactive: o.isReviewInactive,
        );
      }
      if (changed && _isUsingDefaultReviewQuery) {
        ReviewMemoryCache.instance.remember(_currentProduct.id, _reviews);
      }
    });
  }

  Future<void> _afterReviewsRefreshed() async {
    // Kendi yorumu like overlay’i diskten hızlı gelir; tüm satırlar için like count
    // GET’leri (yavaş) ondan sonra veya paralel — önce boost yoksa UI 1–2 sn gecikirdi.
    await _syncSelfLikeBoostFromPrefsAndServer();
    unawaited(_hydrateReviewRowLikeCounts());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      ReviewReportStorage.hydrateForCurrentUser().then((_) {
        if (mounted) setState(() {});
      }),
    );
    final cu = CurrentUserCache.instance;
    if (cu.hasUserId) {
      _currentUserId = cu.userId;
      _currentUsername = cu.userName;
    }
    unawaited(_loadCurrentUserEarly());
    NotificationRealtimeService.instance.attach();
    _reviewDeactivatedSub = NotificationRealtimeService.instance.pushStream
        .listen(_onReviewDeactivatedPush);
    if (widget.product != null) {
      _currentProduct = widget.product!;
      if (!isProductEntityActive(_currentProduct)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _exitProductPageBecauseUnavailable();
        });
        return;
      }
      ProductMemoryCache.instance.remember(_currentProduct);
      _hydrateReviewsFromCache();
      if (_reviews.isNotEmpty) {
        unawaited(_syncSelfLikeBoostFromPrefsAndServer());
      }
      _loadReviews(background: _reviews.isNotEmpty);
      unawaited(_loadLikeCount());
      unawaited(_refreshProductData());
      _startProductListingPoll();
      return;
    }
    final pid = widget.productId!;
    final warm = ProductMemoryCache.instance.peek(pid);
    if (warm != null) {
      _currentProduct = warm;
      if (!isProductEntityActive(_currentProduct)) {
        _isLoadingProduct = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _exitProductPageBecauseUnavailable();
        });
        return;
      }
      _isLoadingProduct = false;
      _hydrateReviewsFromCache();
      if (_reviews.isNotEmpty) {
        unawaited(_syncSelfLikeBoostFromPrefsAndServer());
      }
      _loadReviews(background: _reviews.isNotEmpty);
      unawaited(_loadLikeCount());
      unawaited(_refreshProductData());
      _startProductListingPoll();
      return;
    }
    // productId ile açıldı: placeholder ile hemen göster, arka planda ürünü yükle
    _currentProduct = _placeholderProduct(pid, widget.productName ?? '');
    _isLoadingProduct = true;
    _hydrateReviewsFromCache();
    if (_reviews.isNotEmpty) {
      unawaited(_syncSelfLikeBoostFromPrefsAndServer());
    }
    _loadReviews(background: _reviews.isNotEmpty);
    _loadProductById();
    _startProductListingPoll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _productListingPollTimer?.cancel();
    _reviewDeactivatedSub?.cancel();
    NotificationRealtimeService.instance.detach();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ownerGateById.clear();
      _clearLocalReviewQueryCacheForCurrentProduct();
      unawaited(_syncProductPageInBackground());
    }
  }

  void _startProductListingPoll() {
    _productListingPollTimer?.cancel();
    unawaited(_syncProductPageInBackground());
    _productListingPollTimer = Timer.periodic(
      _productListingPollInterval,
      (_) {
        if (!mounted) return;
        unawaited(_syncProductPageInBackground());
      },
    );
  }

  /// GET /api/products/home `page=0&size=50` — hata: yanlış geri sarma riskine karşı 'vitrinde' kabul.
  Future<bool> _isProductIdOnHomeFirst50(
    String productId,
    String? token,
  ) async {
    final id = productId.trim();
    if (id.isEmpty) return true;
    try {
      final feed = await _productRepository.getHomeFeed(
        page: 0,
        size: 50,
        firebaseIdToken: token,
      );
      final on = feed.content.map((e) => e.id.trim()).toSet();
      return on.contains(id);
    } catch (_) {
      return true;
    }
  }

  Future<void> _seedLastHomeProductSnapshot(
    ProductDto p,
    String? token,
  ) async {
    if (!mounted) return;
    final on = await _isProductIdOnHomeFirst50(p.id, token);
    if (!mounted) return;
    _lastProductOnHomeFirstPage = on;
  }

  static bool _productPageDataChanged(ProductDto a, ProductDto b) {
    return a.name != b.name ||
        a.imageURL != b.imageURL ||
        (a.description ?? '') != (b.description ?? '') ||
        a.isProductNotListed != b.isProductNotListed ||
        (a.averageRating ?? 0) != (b.averageRating ?? 0) ||
        a.isLiked != b.isLiked;
  }

  static bool _reviewListDataChanged(
    List<ReviewDto> previous,
    List<ReviewDto> next,
  ) {
    final a = filterVisibleReviews(previous);
    final b = filterVisibleReviews(next);
    if (a.length != b.length) return true;
    final nextById = {for (final r in b) r.id: r};
    for (final x in a) {
      final y = nextById[x.id];
      if (y == null) return true;
      if (x.rating != y.rating || x.likeCount != y.likeCount) return true;
      if (x.title != y.title) return true;
      if ((x.description ?? '') != (y.description ?? '')) return true;
    }
    for (final y in b) {
      if (!a.any((x) => x.id == y.id)) return true;
    }
    return false;
  }

  /// 5 sn: [getProductById] + yorum listesi; değişmediyse [setState] yok. Askı/404’te geri dön.
  void _onReviewDeactivatedPush(NotificationPushEvent event) {
    final n = event.notification;
    if (n == null || n.type != 'REVIEW_DEACTIVATED') return;
    String? eventProductId;
    final raw = n.payloadJson;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map<String, dynamic>) {
          eventProductId = d['productId']?.toString();
        }
      } catch (_) {}
    }
    if (eventProductId == null) return;
    if (eventProductId != _currentProduct.id) return;
    _clearLocalReviewQueryCacheForCurrentProduct();
    unawaited(_syncProductPageInBackground());
  }

  Future<void> _syncProductPageInBackground() async {
    if (!mounted || _poppedBecauseProductUnlisted) return;
    // Placeholder olsa da [productId] varken taze GET ile askı tespit edilebilsin.
    if (_pageBackgroundSyncInFlight) return;
    final id = _currentProduct.id.trim();
    if (id.isEmpty) return;
    _pageBackgroundSyncInFlight = true;
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      // Token yok bile GET /products/{id} ile askı tespiti (cache [bypassCache] ile atlanır).
      final p = await _productRepository.getProductById(
        id,
        firebaseIdToken: token,
        bypassCache: true,
      );
      if (!mounted) return;
      if (p.isUnavailableForStorefront) {
        _exitProductPageBecauseUnavailable();
        return;
      }
      final onHome = await _isProductIdOnHomeFirst50(p.id, token);
      if (!mounted) return;
      if (_lastProductOnHomeFirstPage == true && onHome == false) {
        _exitProductPageBecauseUnavailable();
        return;
      }
      _lastProductOnHomeFirstPage = onHome;
      if (_productPageDataChanged(p, _currentProduct)) {
        if (mounted) {
          setState(() {
            final likedForUi = _effectiveProductLiked();
            _currentProduct = p.copyWith(isLiked: likedForUi);
            _cachedRatingCounts = null;
            if (!_isProductLikeMutationInFlight) {
              _productLikeUiOverride = null;
            }
          });
        }
        ProductMemoryCache.instance.remember(_currentProduct);
      }
      if (!mounted) return;
      String? reviewsToken;
      if (FirebaseAuth.instance.currentUser != null) {
        reviewsToken = await _sessionHelper.ensureSession();
        if (!mounted) return;
        // Token null olsa bile review listesi güncellenmeli; erken çıkma.
      }
      final reviews = await _fetchReviewsWithCurrentFilters(
        firebaseIdToken: reviewsToken,
      );
      if (!mounted) return;
      _rememberReviewQueryCache(reviews);
      if (_isUsingDefaultReviewQuery) {
        ReviewMemoryCache.instance.remember(_currentProduct.id, reviews);
      }
      final nextAvg = reviews.isEmpty ? 0.0 : _averageRatingFromReviews(reviews);
      final avgChanged = (_currentProduct.averageRating ?? 0) != nextAvg;
      if (_reviewListDataChanged(_reviews, reviews) || avgChanged) {
        if (mounted) {
          setState(() {
            _reviews = _mergeReviewsPreservingLikeInFlight(reviews);
            _currentProduct = _currentProduct.copyWith(averageRating: nextAvg);
            _cachedRatingCounts = null;
          });
          ProductMemoryCache.instance.remember(_currentProduct);
        }
      }
      if (mounted && FirebaseAuth.instance.currentUser != null) {
        unawaited(_loadLikeCount());
        unawaited(_refreshProductLikeStatus());
      }
    } on ProductNotAvailableException {
      if (!mounted) return;
      _exitProductPageBecauseUnavailable();
    } catch (_) {
    } finally {
      _pageBackgroundSyncInFlight = false;
    }
  }

  /// Unlisted or missing product: dialog, then [HomePage] (clear stack).
  void _exitProductPageBecauseUnavailable() {
    if (!mounted || _poppedBecauseProductUnlisted) return;
    _poppedBecauseProductUnlisted = true;
    _productListingPollTimer?.cancel();
    _productListingPollTimer = null;
    final id = _currentProduct.id.trim();
    if (id.isNotEmpty) {
      ProductMemoryCache.instance.remove(id);
    }
    unawaited(
      showContentUnavailableDialog(
        context,
        title: kTitleProductUnavailable,
        message: kMessageProductNoLongerAvailable,
        onContinue: () async {
          if (!mounted) return;
          await Navigator.of(context).pushAndRemoveUntil<void>(
            MaterialPageRoute<void>(builder: (_) => const HomePage()),
            (route) => false,
          );
        },
      ),
    );
  }

  /// Review satırında kendi incelemeni tespit et: [getMe] ürün/review cevabından önce tamamlanır, gri→kırmızı flash olmaz.
  Future<void> _loadCurrentUserEarly() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final warm = CurrentUserCache.instance;
    if (warm.hasUserId) {
      if (mounted) {
        setState(() {
          _currentUserId = warm.userId;
          _currentUsername = warm.userName;
        });
      } else {
        _currentUserId = warm.userId;
        _currentUsername = warm.userName;
      }
    }
    if (_currentUserId != null && _currentUsername != null) return;
    try {
      final t = await _sessionHelper.ensureSession();
      if (t == null || !mounted) return;
      final me = await AuthService().getMe();
      if (!mounted) return;
      setState(() {
        _currentUsername = me.userName;
        _currentUserId = me.id;
      });
    } catch (_) {}
  }

  void _hydrateReviewsFromCache() {
    if (!_isUsingDefaultReviewQuery) return;
    final cached = ReviewMemoryCache.instance.peek(_currentProduct.id);
    if (cached == null || cached.isEmpty) return;
    _reviews = filterVisibleReviews(cached);
    _isLoadingReviews = false;
    _errorMessage = null;
  }

  ProductDto _placeholderProduct(String id, String name) {
    return ProductDto(
      id: id,
      name: name.isNotEmpty ? name : '...',
      imageURL: '',
      tag: TagDto(id: '', name: ''),
    );
  }

  Future<void> _loadProductById() async {
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      final product = await _productRepository.getProductById(
        widget.productId!,
        firebaseIdToken: token,
        bypassCache: true,
      );
      if (!mounted) return;
      setState(() {
        _currentProduct = product;
        _isLoadingProduct = false;
      });
      if (product.isUnavailableForStorefront) {
        _exitProductPageBecauseUnavailable();
        return;
      }
      unawaited(_seedLastHomeProductSnapshot(product, token));
      await _loadLikeCount();
      unawaited(_refreshProductLikeStatus());
    } on ProductNotAvailableException {
      if (!mounted) return;
      setState(() {
        _isLoadingProduct = false;
      });
      _exitProductPageBecauseUnavailable();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingProduct = false;
      });
    }
  }

  Future<void> _loadLikeCount({bool skipDuringLikeMutation = true}) async {
    if (skipDuringLikeMutation && _isProductLikeMutationInFlight) return;
    final seq = ++_likeCountFetchSeq;
    try {
      final count = await _interactionRepository.getProductLikeCount(
        _currentProduct.id,
      );
      if (!mounted) return;
      if (seq != _likeCountFetchSeq) return;
      setState(() {
        _likeCount = count;
      });
    } catch (e, st) {
      AppLogger.warnSilencedError('_loadLikeCount', e, st);
      if (!mounted) return;
    }
  }

  bool _effectiveProductLiked() =>
      _productLikeUiOverride ?? (_currentProduct.isLiked ?? false);

  Future<void> _refreshProductLikeStatus({
    bool skipDuringLikeMutation = true,
  }) async {
    if (skipDuringLikeMutation && _isProductLikeMutationInFlight) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await _sessionHelper.getTokenAndSetHeader();
    if (token == null || !mounted) return;
    final seq = ++_productLikeStatusFetchSeq;
    try {
      final liked = await _interactionRepository.isProductLiked(
        token,
        _currentProduct.id,
      );
      if (!mounted || seq != _productLikeStatusFetchSeq) return;
      if (_isProductLikeMutationInFlight) return;
      setState(() {
        _currentProduct = _currentProduct.copyWith(isLiked: liked);
        _productLikeUiOverride = null;
      });
    } catch (e, st) {
      AppLogger.warnSilencedError('_refreshProductLikeStatus', e, st);
    }
  }

  bool _isUnauthorizedError(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 401 || code == 403) return true;
      final payload = dioResponseDataAsSearchString(error.response?.data)
          .toLowerCase();
      if (payload.contains('authentication required')) return true;
      if (payload.contains('unauthorized')) return true;
      if ((error.message ?? '').toLowerCase().contains('unauthorized')) {
        return true;
      }
    }
    final asText = error.toString().toLowerCase();
    return asText.contains('authentication required') ||
        asText.contains('unauthorized');
  }

  Future<List<ReviewDto>> _fetchReviewsWithCurrentFilters({
    String? firebaseIdToken,
    bool forceOwnerProfileRefresh = false,
  }) async {
    Future<List<ReviewDto>> run(String? token) async {
      return filterVisibleReviews(
        await _reviewRepository.getReviewsByProductId(
          _currentProduct.id,
          firebaseIdToken: token,
          hasMedia: _hasMediaFilter,
          isCollaborative: _isCollaborativeFilter,
          sort: _selectedSort,
        ),
      );
    }

    List<ReviewDto>? list;
    try {
      list = await run(firebaseIdToken);
    } catch (e) {
      if (!_isUnauthorizedError(e)) rethrow;
      final refreshed = await _sessionHelper.refreshSession();
      if (refreshed != null) {
        try {
          list = await run(refreshed);
        } catch (retryError) {
          if (!_isUnauthorizedError(retryError)) rethrow;
        }
      }
      if (list == null) {
        if (_hasBinaryReviewFilters) {
          final probe = await _sessionHelper.ensureSession();
          if (probe != null) {
            await _reviewRepository.getReviewsByProductId(
              _currentProduct.id,
              firebaseIdToken: probe,
              sort: _selectedSort,
            );
            list = <ReviewDto>[];
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
    }
    return _filterReviewsHidingBlockedOwners(
      list,
      forceRefreshBlockedCache: forceOwnerProfileRefresh,
    );
  }

  Future<void> _onChatIconTap(ReviewDto review) async {
    if (!isProductEntityActive(_currentProduct) || !isReviewEntityVisible(review)) {
      return;
    }
    final pageContext = context;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Please login to send messages',
          variant: CustomSnackBarVariant.error,
        );
      }
      return;
    }

    final controller = TextEditingController();
    bool isSending = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.xLarge,
            right: AppSpacing.xLarge,
            top: AppSpacing.large,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.large,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              Future<void> send() async {
                final text = controller.text.trim();
                if (text.isEmpty || isSending) return;
                setState(() => isSending = true);
                try {
                  final token = await _sessionHelper.ensureSession();
                  if (token == null) {
                    throw Exception('Failed to get Firebase ID token');
                  }
                  await _messageRepository.sendMessage(
                    recipientId: int.tryParse(review.ownerId),
                    content: text,
                  );
                  if (!context.mounted) return;
                  FocusManager.instance.primaryFocus?.unfocus();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!pageContext.mounted) return;
                      CustomSnackBar.show(
                        pageContext,
                        message:
                            'Message sent to @${review.ownerUserName}',
                        variant: CustomSnackBarVariant.success,
                      );
                    });
                  });
                } catch (e) {
                  final msg = ErrorHandler.getUserFriendlyMessage(e);
                  if (context.mounted) {
                    CustomSnackBar.show(
                      context,
                      message: msg,
                      variant: CustomSnackBarVariant.error,
                    );
                  } else if (mounted && pageContext.mounted) {
                    CustomSnackBar.show(
                      pageContext,
                      message: msg,
                      variant: CustomSnackBarVariant.error,
                    );
                  }
                  if (context.mounted) {
                    setState(() => isSending = false);
                  }
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Message @${review.ownerUserName}',
                    style: AppTextStyles.heading3,
                  ),
                  const SizedBox(height: AppSpacing.medium),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: 'Write your message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.medium),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: isSending ? null : send,
                      child:
                          isSending
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text('Send'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    controller.dispose();
  }

  /// Product'ı backend'den yeniden yükler (rating ve like durumu için)
  Future<void> _refreshProductData() async {
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      final updatedProduct = await _productRepository.getProductById(
        _currentProduct.id,
        firebaseIdToken: token,
        bypassCache: true,
      );

      if (!mounted) return;
      if (updatedProduct.isUnavailableForStorefront) {
        _exitProductPageBecauseUnavailable();
        return;
      }
      final onHome = await _isProductIdOnHomeFirst50(updatedProduct.id, token);
      if (!mounted) return;
      if (_lastProductOnHomeFirstPage == true && onHome == false) {
        _exitProductPageBecauseUnavailable();
        return;
      }
      _lastProductOnHomeFirstPage = onHome;
      setState(() {
        final likedForUi = _effectiveProductLiked();
        if (!_isLoadingReviews) {
          final nextAvg = _reviews.isEmpty
              ? 0.0
              : _averageRatingFromReviews(_reviews);
          _currentProduct = updatedProduct.copyWith(
            averageRating: nextAvg,
            isLiked: likedForUi,
          );
        } else {
          _currentProduct = updatedProduct.copyWith(isLiked: likedForUi);
        }
        if (!_isProductLikeMutationInFlight) {
          _productLikeUiOverride = null;
        }
      });
      ProductMemoryCache.instance.remember(_currentProduct);
      unawaited(_refreshProductLikeStatus());
    } on ProductNotAvailableException {
      if (!mounted) return;
      _exitProductPageBecauseUnavailable();
    } catch (_) {}
  }

  /// Arka plan [_loadReviews] / poll, like isteği sürerken eski satırı geri yazmasın.
  List<ReviewDto> _mergeReviewsPreservingLikeInFlight(List<ReviewDto> fetched) {
    if (fetched.isEmpty) return fetched;
    final prev = {for (final r in _reviews) r.id: r};
    return [
      for (final r in fetched)
        if (_reviewListLikeLock.isHeld(r.id) && prev.containsKey(r.id))
          prev[r.id]!
        else
          r,
    ];
  }

  /// [getReviewById] bazen toggle’dan önceki [isLiked] ile döner; [toggleReviewLike] otoritedir.
  ReviewDto _reviewRowWithToggleLikeReconciled(
    ReviewDto fromServer,
    bool toggleLiked,
    ReviewDto optimisticRow,
  ) {
    if (fromServer.isLikedByCurrentUser == toggleLiked) return fromServer;
    return ReviewDto(
      id: fromServer.id,
      title: fromServer.title,
      description: fromServer.description,
      isCollaborative: fromServer.isCollaborative,
      rating: fromServer.rating,
      createdAt: fromServer.createdAt,
      productId: fromServer.productId,
      productName: fromServer.productName,
      ownerId: fromServer.ownerId,
      ownerUserName: fromServer.ownerUserName,
      ownerProfilePhotoUrl: fromServer.ownerProfilePhotoUrl,
      mediaList: fromServer.mediaList,
      likeCount: optimisticRow.likeCount,
      isLikedByCurrentUser: toggleLiked,
      isProductNotListed: fromServer.isProductNotListed,
      isReviewInactive: fromServer.isReviewInactive,
    );
  }

  Future<void> _loadReviews({bool background = false}) async {
    var shouldFetchInBackground = background;
    if (!background) {
      final cached = _peekFreshReviewQueryCache();
      if (cached != null) {
        setState(() {
          _reviews = cached;
          _currentProduct = _currentProduct.copyWith(
            averageRating: cached.isEmpty ? 0.0 : _averageRatingFromReviews(cached),
          );
          _cachedRatingCounts = null;
          _isLoadingReviews = false;
          _errorMessage = null;
        });
        unawaited(_afterReviewsRefreshed());
        shouldFetchInBackground = true;
      } else {
        setState(() {
          _isLoadingReviews = true;
          _errorMessage = null;
        });
      }
    } else {
      _errorMessage = null;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Kullanıcı giriş yapmamışsa, review'ları token olmadan çekmeyi dene
        try {
          final reviews = await _fetchReviewsWithCurrentFilters(
            firebaseIdToken: null,
          );
          _rememberReviewQueryCache(reviews);
          if (_isUsingDefaultReviewQuery) {
            ReviewMemoryCache.instance.remember(_currentProduct.id, reviews);
          }
          setState(() {
            _reviews = _mergeReviewsPreservingLikeInFlight(reviews);
            _currentProduct = _currentProduct.copyWith(
              averageRating: reviews.isEmpty ? 0.0 : _averageRatingFromReviews(reviews),
            );
            _cachedRatingCounts = null;
            _isLoadingReviews = false;
            _errorMessage = null;
          });
          ProductMemoryCache.instance.remember(_currentProduct);
          unawaited(_afterReviewsRefreshed());
          return;
        } catch (e) {
          setState(() {
            _reviews = [];
            _currentProduct = _currentProduct.copyWith(averageRating: 0.0);
            _errorMessage = _guestReviewsLoginMessage;
            _isLoadingReviews = false;
          });
          return;
        }
      }

      // Ensure session and get token
      final firebaseIdToken = await _sessionHelper.ensureSession();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Mevcut kullanıcı (önbellek veya getMe) — sadece bir kez
      if (_currentUsername == null) {
        final c = CurrentUserCache.instance;
        if (c.hasUserId) {
          _currentUsername = c.userName;
          _currentUserId = c.userId;
        }
      }
      if (_currentUsername == null) {
        try {
          final authService = AuthService();
          final me = await authService.getMe();
          _currentUsername = me.userName;
          _currentUserId = me.id;
        } catch (_) {}
      }

      // Review'ları çek
      final reviews = await _fetchReviewsWithCurrentFilters(
        firebaseIdToken: firebaseIdToken,
      );
      _rememberReviewQueryCache(reviews);
      if (_isUsingDefaultReviewQuery) {
        ReviewMemoryCache.instance.remember(_currentProduct.id, reviews);
      }

      setState(() {
        _reviews = _mergeReviewsPreservingLikeInFlight(reviews);
        _currentProduct = _currentProduct.copyWith(
          averageRating: reviews.isEmpty ? 0.0 : _averageRatingFromReviews(reviews),
        );
        _cachedRatingCounts = null;
        _isLoadingReviews = false;
        _errorMessage = null;
      });
      ProductMemoryCache.instance.remember(_currentProduct);
      unawaited(_afterReviewsRefreshed());
    } catch (e, st) {
      if (shouldFetchInBackground && _reviews.isNotEmpty) return;
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      if (isLoggedIn && _isUnauthorizedError(e)) {
        setState(() {
          _reviews = [];
          _currentProduct = _currentProduct.copyWith(averageRating: 0.0);
          _cachedRatingCounts = null;
          _errorMessage = null;
          _isLoadingReviews = false;
        });
        return;
      }
      // Ağ / sunucu hatası veya tüm yorumlar gizlendi: vitrinde “0 yorum” ürünü gibi davran.
      AppLogger.warnSilencedError('ReviewPage._loadReviews', e, st);
      if (!mounted) return;
      setState(() {
        _reviews = [];
        _currentProduct = _currentProduct.copyWith(averageRating: 0.0);
        _cachedRatingCounts = null;
        _errorMessage = null;
        _isLoadingReviews = false;
      });
      ProductMemoryCache.instance.remember(_currentProduct);
    }
  }

  Future<void> _handleDeleteReview(ReviewDto review) async {
    if (!_reviewDeleteLock.tryEnter(review.id)) return;
    try {
      final ok = await ReviewDeleteFlow.confirmAndDelete(
        context,
        repository: _reviewRepository,
        sessionHelper: _sessionHelper,
        reviewId: review.id,
      );
      if (!mounted || !ok) return;
      _clearLocalReviewQueryCacheForCurrentProduct();
      setState(() {
        _reviews.removeWhere((r) => r.id == review.id);
        _currentProduct = _currentProduct.copyWith(
          averageRating: _reviews.isEmpty ? 0.0 : _averageRatingFromReviews(_reviews),
        );
        _cachedRatingCounts = null;
      });
      ProductMemoryCache.instance.remember(_currentProduct);
      ReviewMemoryCache.instance.removeReviewFromProduct(
        _currentProduct.id,
        review.id,
      );
    } finally {
      _reviewDeleteLock.leave(review.id);
    }
  }

  Future<void> _toggleLike() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Please login to like products',
          variant: CustomSnackBarVariant.error,
        );
      }
      return;
    }
    if (!_productPageLikeLock.tryEnter()) {
      // Spam tap: tek tek kuyruğa dizmek yerine parity tut.
      // Çift ek dokunuş nötr, tek ek dokunuş bir toggle daha demek.
      _queuedProductLikeToggleParity = !_queuedProductLikeToggleParity;
      return;
    }

    // Optimistic update - UI'ı hemen güncelle (loading indicator yok)
    final previousLikeStatus = _effectiveProductLiked();
    final previousLikeCount = _likeCount;
    final optimisticLikeStatus = !previousLikeStatus;
    _isProductLikeMutationInFlight = true;
    setState(() {
      _productLikeUiOverride = optimisticLikeStatus;
      _currentProduct = _currentProduct.copyWith(isLiked: optimisticLikeStatus);
      _likeCount = (_likeCount + (previousLikeStatus ? -1 : 1)).clamp(0, 999999);
    });

    try {
      // Token al (session zaten var, sadece token'ı header'a ekle)
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (token == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Backend'e like toggle isteği gönder
      final newLikeStatus = await _interactionRepository.toggleProductLike(
        token,
        _currentProduct.id,
      );

      // Backend'den gelen gerçek durumu güncelle
      setState(() {
        _productLikeUiOverride = newLikeStatus;
        _currentProduct = _currentProduct.copyWith(isLiked: newLikeStatus);
        final delta =
            newLikeStatus == previousLikeStatus ? 0 : (newLikeStatus ? 1 : -1);
        _likeCount = (previousLikeCount + delta).clamp(0, 999999);
      });
      unawaited(_loadLikeCount(skipDuringLikeMutation: false));
      unawaited(_refreshProductLikeStatus(skipDuringLikeMutation: false));
    } catch (e) {
      // Hata durumunda optimistic update'i geri al
      setState(() {
        _productLikeUiOverride = previousLikeStatus;
        _currentProduct = _currentProduct.copyWith(isLiked: previousLikeStatus);
        _likeCount = previousLikeCount;
      });

      if (mounted) {
        final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        CustomSnackBar.show(
          context,
          message: errorMessage,
          variant: CustomSnackBarVariant.error,
        );
      }
    } finally {
      _isProductLikeMutationInFlight = false;
      if (_queuedProductLikeToggleParity) {
        // Sonraki queued toggle bu override'ı yeniden yazacak.
      } else {
        _productLikeUiOverride = null;
      }
      _productPageLikeLock.leave();
      if (_queuedProductLikeToggleParity) {
        _queuedProductLikeToggleParity = false;
        unawaited(_toggleLike());
      }
    }
  }

  void _openImagePreview() {
    final imageUrl = _currentProduct.imageURL;
    if (imageUrl.trim().isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Hero(
                    tag:
                        'product_image_${_currentProduct.id}_${_currentProduct.imageURL}',
                    child: InteractiveViewer(
                      panEnabled: true,
                      clipBehavior: Clip.none,
                      minScale: 1,
                      maxScale: 5,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (context, error, stackTrace) => Container(
                              width: 240,
                              height: 240,
                              color: AppColors.textSecondary.withValues(alpha: 0.1),
                              child: const Icon(
                                Icons.image_not_supported,
                                size: 42,
                                color: AppColors.textSecondary,
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_poppedBecauseProductUnlisted) {
      return const Scaffold(
        body: SizedBox.shrink(),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? value) {
        if (didPop) return;
        if (!context.mounted) return;
        Navigator.of(context).pop(
          ReviewPagePopResult(
            product: _currentProduct,
            likeCount: _likeCount,
            reviewCount: _reviews.length,
          ),
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: false,
        toolbarHeight: 62,
        titleSpacing: 4,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFB5003A),
                AppColors.primary,
                Color(0xFF6B001F),
              ],
            ),
          ),
        ),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          onPressed: () {
            Navigator.of(context).pop(
              ReviewPagePopResult(
                product: _currentProduct,
                likeCount: _likeCount,
                reviewCount: _reviews.length,
              ),
            );
          },
        ),
        title: Text(
          _currentProduct.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            height: 1.1,
            color: Colors.white,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              onPressed: !isProductEntityActive(_currentProduct) || _isLoadingProduct
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductAiChatPage(
                            productId: _currentProduct.id,
                            productName: _currentProduct.name,
                          ),
                        ),
                      );
                    },
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Opacity(
                    opacity: (!isProductEntityActive(_currentProduct) ||
                            _isLoadingProduct)
                        ? 0.38
                        : 1.0,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        'assets/images/chatbot_white.png',
                        fit: BoxFit.contain,
                        semanticLabel: 'Product AI Chat',
                      ),
                    ),
                  ),
                ),
              ),
              tooltip: 'Product AI Chat',
            ),
          ),
        ],
      ),
      body: CustomRefreshIndicator(
        onRefresh: () async {
          _ownerGateById.clear();
          _clearLocalReviewQueryCacheForCurrentProduct();
          await Future.wait([_loadReviews(), _refreshProductData()]);
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(
              top: 0,
              bottom: AppSpacing.xxLarge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// HERO PRODUCT CARD
                Padding(
                  padding: _contentHorizontalPadding,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.medium),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.7),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: _openImagePreview,
                            child: Hero(
                              tag:
                                  'product_image_${_currentProduct.id}_${_currentProduct.imageURL}',
                              child: Container(
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.network(
                                    _currentProduct.imageURL,
                                    height: 220,
                                    width: 220,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.center,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        height: 220,
                                        width: 220,
                                        color: AppColors.textSecondary.withValues(
                                          alpha: 0.1,
                                        ),
                                        child: const Icon(
                                          Icons.image_not_supported,
                                          color: AppColors.textSecondary,
                                          size: 44,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.medium),
                        _buildProductCategoryBreadcrumb(),
                        const SizedBox(height: AppSpacing.small),
                        if ((_currentProduct.description ?? '').trim().isEmpty)
                          Text(
                            'No product description yet.',
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.4,
                              fontSize: 15,
                            ),
                          )
                        else ...[
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final descStyle = AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.35,
                                fontSize: 15,
                              );
                              final description = _currentProduct.description!;
                              final canExpand = _shouldShowDescriptionToggle(
                                text: description,
                                style: descStyle,
                                maxWidth: constraints.maxWidth,
                              );

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    description,
                                    maxLines:
                                        (_isDescriptionExpanded || !canExpand)
                                            ? null
                                            : 3,
                                    overflow:
                                        (_isDescriptionExpanded || !canExpand)
                                            ? TextOverflow.visible
                                            : TextOverflow.ellipsis,
                                    textAlign: TextAlign.justify,
                                    style: descStyle,
                                  ),
                                  if (canExpand) ...[
                                    const SizedBox(height: 2),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed:
                                            () => setState(
                                              () =>
                                                  _isDescriptionExpanded =
                                                      !_isDescriptionExpanded,
                                            ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 0,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _isDescriptionExpanded
                                                  ? 'Show less'
                                                  : 'Read more',
                                              style: AppTextStyles.bodySmall
                                                  .copyWith(
                                                    color:
                                                        AppColors.textSecondary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              _isDescriptionExpanded
                                                  ? Icons.expand_less_rounded
                                                  : Icons.expand_more_rounded,
                                              size: 18,
                                              color: AppColors.textSecondary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: AppSpacing.medium),
                        Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: SizedBox(
                                height: 48,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () async {
                                    final my = _myReview;
                                    final result = await Navigator.push(
                                      context,
                                      SlideUpRoute(
                                        page: AddReviewPage(
                                          product: _currentProduct,
                                          reviewToEdit: my,
                                        ),
                                      ),
                                    );
                                    if (result == true) {
                                      await Future.wait([
                                        _loadReviews(),
                                        _refreshProductData(),
                                      ]);
                                    }
                                  },
                                  child: Text(_myReview != null ? 'Edit your review' : 'Add a Review'),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.medium),
                            Expanded(
                              flex: 1,
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: _toggleLike,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: _effectiveProductLiked()
                                          ? AppColors.primary
                                          : AppColors.border,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    backgroundColor: _effectiveProductLiked()
                                        ? AppColors.primary.withValues(alpha: 0.07)
                                        : Colors.transparent,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Icon(
                                    _effectiveProductLiked()
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 22,
                                    color: _effectiveProductLiked()
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.small),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$_likeCount likes',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _miniIconAction(
                                  icon: Icons.compare_arrows_outlined,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => CompareProductSelectPage(
                                              product1: _currentProduct,
                                            ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.small),
                        Builder(
                          builder: (context) {
                            // Görünür yorumlar yüklendikten sonra özet; sunucu [averageRating]
                            // askılı yazarları hâlâ sayıyor olabilir.
                            final bool preferList =
                                !_isLoadingReviews || _reviews.isNotEmpty;
                            final double rawRating;
                            if (preferList && _reviews.isNotEmpty) {
                              final sum =
                                  _reviews.fold<int>(0, (s, r) => s + r.rating);
                              rawRating = sum / _reviews.length;
                            } else if (preferList && _reviews.isEmpty) {
                              rawRating = 0.0;
                            } else {
                              rawRating = _currentProduct.averageRating ?? 0.0;
                            }
                            final hasRating = productHasMeaningfulRating(rawRating);
                            final rating =
                                (rawRating.isNaN || rawRating.isInfinite)
                                    ? 0.0
                                    : rawRating.clamp(0.0, 5.0);

                            if (!hasRating) return const SizedBox.shrink();

                            return Container(
                              padding: const EdgeInsets.all(AppSpacing.small),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.border.withValues(alpha: 0.75),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap:
                                        () => setState(
                                          () =>
                                              _isRatingExpanded =
                                                  !_isRatingExpanded,
                                        ),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                        horizontal: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          ...List.generate(5, (index) {
                                            if (rating >= index + 1) {
                                              return const Icon(
                                                Icons.star,
                                                size: 20,
                                                color: AppColors.primary,
                                              );
                                            } else if (rating > index &&
                                                rating < index + 1) {
                                              return SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: Stack(
                                                  children: [
                                                    const Icon(
                                                      Icons.star_border,
                                                      size: 20,
                                                      color:
                                                          AppColors.textSecondary,
                                                    ),
                                                    ClipRect(
                                                      child: Align(
                                                        alignment:
                                                            Alignment.centerLeft,
                                                        widthFactor:
                                                            rating - index,
                                                        child: const Icon(
                                                          Icons.star,
                                                          size: 20,
                                                          color:
                                                              AppColors.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            return const Icon(
                                              Icons.star_border,
                                              size: 20,
                                              color: AppColors.textSecondary,
                                            );
                                          }),
                                          const SizedBox(width: 8),
                                          Text(
                                            rating.toStringAsFixed(1),
                                            style: AppTextStyles.bodyBold
                                                .copyWith(
                                                  color: AppColors.textPrimary,
                                                  fontSize: 16,
                                                ),
                                          ),
                                          const Spacer(),
                                          Icon(
                                            _isRatingExpanded
                                                ? Icons.keyboard_arrow_up_rounded
                                                : Icons
                                                    .keyboard_arrow_down_rounded,
                                            color: AppColors.textSecondary,
                                            size: 22,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  AnimatedCrossFade(
                                    duration: const Duration(milliseconds: 220),
                                    firstChild: const SizedBox.shrink(),
                                    secondChild: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: _buildRatingDistribution(),
                                    ),
                                    crossFadeState:
                                        _isRatingExpanded
                                            ? CrossFadeState.showSecond
                                            : CrossFadeState.showFirst,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.large),

                /// REVIEWS TITLE
                Padding(
                  padding: _contentHorizontalPadding,
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text("Reviews", style: AppTextStyles.heading2),
                      const Spacer(),
                      _buildControlIconButton(
                        icon: Icons.swap_vert_rounded,
                        isActive: _selectedSort != _sortNewest,
                        tooltip: 'Sort reviews',
                        onTap: () {
                          unawaited(_openSortSheet());
                        },
                      ),
                      const SizedBox(width: 8),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _buildControlIconButton(
                            icon: Icons.tune_rounded,
                            isActive: _activeFilterCount > 0,
                            tooltip: 'Filter reviews',
                            onTap: () {
                              unawaited(_openFilterSheet());
                            },
                          ),
                          if (_activeFilterCount > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                width: 16,
                                height: 16,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$_activeFilterCount',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      if (_reviews.isNotEmpty)
                        Text(
                          '${_reviews.length} review${_reviews.length > 1 ? 's' : ''}',
                          style: AppTextStyles.bodySecondary.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.large),

                /// REVIEWS LIST
                if (_isLoadingReviews)
                  const SizedBox(height: AppSpacing.xxLarge)
                else if (_reviews.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxLarge,
                        vertical: AppSpacing.xxLarge,
                      ),
                      child: Text(
                        _errorMessage == _guestReviewsLoginMessage
                            ? _guestReviewsLoginMessage
                            : _emptyReviewsMessage(),
                        style: AppTextStyles.bodySecondary,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ..._reviews.map(
                    (review) {
                      final displayReview =
                          SelfReviewLikeDisplay.mergeServerRowWithBoostMap(
                        review,
                        _selfLikeBoostByReviewId,
                      );
                      return Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.xxLarge,
                        right: AppSpacing.xxLarge,
                        bottom: AppSpacing.large,
                      ),
                      child: ReviewCard(
                        username: '@${review.ownerUserName}',
                        content: review.description ?? review.title,
                        rating: review.rating,
                        reviewDateLabel: _formatReviewRelativeDate(
                          review.createdAt,
                        ),
                        isSponsored: review.isCollaborative,
                        likeCount: displayReview.likeCount,
                        isLiked: displayReview.isLikedByCurrentUser,
                        isCurrentUser: _isMyReview(review),
                        hasMedia: review.mediaList.isNotEmpty,
                        showChatIcon:
                            _currentUsername != null &&
                            isProductEntityActive(_currentProduct) &&
                            isReviewEntityVisible(review) &&
                            review.ownerUserName.toLowerCase() !=
                                _currentUsername!.toLowerCase(),
                        hasReportedReview:
                            ReviewReportStorage.hasReportedSync(review.id),
                        onReportTap:
                            _isMyReview(review)
                                ? null
                                : () async {
                                  await openReviewReportFlow(
                                    context,
                                    reviewId: review.id,
                                  );
                                  if (mounted) setState(() {});
                                },
                        onDeleteTap:
                            _isMyReview(review)
                                ? () => _handleDeleteReview(review)
                                : null,
                        onChatTap: () => _onChatIconTap(review),
                        onUsernameTap: () {
                          if (_isMyReview(review)) {
                            return;
                          }
                          openUserProfileIfActive(
                            context,
                            userId: review.ownerId,
                            userName: review.ownerUserName,
                            profileImageUrl: review.ownerProfilePhotoUrl,
                          );
                        },
                        onTap: () async {
                          final result = await Navigator.push<dynamic>(
                            context,
                            SlideRightRoute(
                              page: ReviewDetailPage(
                                review: displayReview,
                                product: _currentProduct,
                              ),
                            ),
                          );
                          if (result == true ||
                              result == ReviewDeleteFlow.popResultDeleted) {
                            _clearLocalReviewQueryCacheForCurrentProduct();
                            await _loadReviews();
                          }
                        },
                        onLikeTap: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            if (mounted) {
                              CustomSnackBar.show(
                                context,
                                message: 'Please login to upvote reviews',
                                variant: CustomSnackBarVariant.error,
                              );
                            }
                            return;
                          }
                          if (!_reviewListLikeLock.tryEnter(review.id)) {
                            return;
                          }
                          final boostBeforeTap =
                              _selfLikeBoostByReviewId[review.id] == true;
                          int reviewIndex = _reviews.indexWhere(
                            (r) => r.id == review.id,
                          );
                          try {
                          // Optimistic update - UI'ı hemen güncelle
                          if (reviewIndex != -1) {
                            if (_isMyReview(review)) {
                              final displayLiked =
                                  review.isLikedByCurrentUser ||
                                  boostBeforeTap;
                              final target = !displayLiked;
                              setState(() {
                                if (target &&
                                    !review.isLikedByCurrentUser) {
                                  _selfLikeBoostByReviewId[review.id] = true;
                                } else {
                                  _selfLikeBoostByReviewId.remove(review.id);
                                }
                              });
                              final uidOptimistic =
                                  _currentUserId?.trim() ??
                                  CurrentUserCache.instance.userId
                                      ?.trim() ??
                                  '';
                              if (uidOptimistic.isNotEmpty) {
                                unawaited(
                                  SelfReviewLikeLocalPrefs.instance.setBoost(
                                    uidOptimistic,
                                    review.id,
                                    _selfLikeBoostByReviewId[review.id] ==
                                        true,
                                  ),
                                );
                              }
                            } else {
                            final previousLikeStatus =
                                _reviews[reviewIndex].isLikedByCurrentUser;
                            final previousLikeCount =
                                _reviews[reviewIndex].likeCount;

                            setState(() {
                              _reviews[reviewIndex] = ReviewDto(
                                id: review.id,
                                title: review.title,
                                description: review.description,
                                isCollaborative: review.isCollaborative,
                                rating: review.rating,
                                createdAt: review.createdAt,
                                productId: review.productId,
                                productName: review.productName,
                                ownerId: review.ownerId,
                                ownerUserName: review.ownerUserName,
                                ownerProfilePhotoUrl: review.ownerProfilePhotoUrl,
                                mediaList: review.mediaList,
                                likeCount:
                                    previousLikeStatus
                                        ? (previousLikeCount > 0
                                            ? previousLikeCount - 1
                                            : 0)
                                        : previousLikeCount + 1,
                                isLikedByCurrentUser: !previousLikeStatus,
                                isProductNotListed: review.isProductNotListed,
                                isReviewInactive: review.isReviewInactive,
                              );
                            });
                            }
                          }

                          try {
                            // Token al (session zaten var)
                            final token =
                                await _sessionHelper.getTokenAndSetHeader();
                            if (token == null) {
                              throw Exception(
                                'Failed to get Firebase ID token',
                              );
                            }

                            // Upvote toggle yap
                            final newLikeStatus = await _interactionRepository
                                .toggleReviewLike(token, review.id);

                            final uid =
                                _currentUserId?.trim() ??
                                CurrentUserCache.instance.userId?.trim() ??
                                '';
                            // Kendi yorumu: toggle true dönse bile GET/liste gecikmeli false verebilir;
                            // boost’u true bırak; [_syncSelfLikeBoostFromPrefsAndServer] sunucu true olunca siler.
                            if (uid.isNotEmpty && _isMyReview(review)) {
                              await SelfReviewLikeLocalPrefs.instance.setBoost(
                                uid,
                                review.id,
                                newLikeStatus,
                              );
                              if (mounted) {
                                setState(() {
                                  if (newLikeStatus) {
                                    _selfLikeBoostByReviewId[review.id] = true;
                                  } else {
                                    _selfLikeBoostByReviewId.remove(review.id);
                                  }
                                });
                              }
                            }

                            // Review'ı backend'den yeniden çek (güncel like durumu için)
                            try {
                              final updatedReview = await _reviewRepository
                                  .getReviewById(
                                    review.id,
                                    firebaseIdToken: token,
                                  );
                              if (!isReviewEntityVisible(updatedReview)) {
                                if (reviewIndex != -1 && mounted) {
                                  setState(() {
                                    _reviews.removeAt(reviewIndex);
                                    _cachedRatingCounts = null;
                                  });
                                  ReviewMemoryCache.instance.remember(
                                    _currentProduct.id,
                                    _reviews,
                                  );
                                  if (context.mounted) {
                                    CustomSnackBar.show(
                                      context,
                                      message:
                                          kMessageReviewNoLongerAvailable,
                                      variant: CustomSnackBarVariant.neutral,
                                    );
                                  }
                                }
                                return;
                              }
                              if (mounted) {
                                final ri =
                                    _reviews.indexWhere((r) => r.id == review.id);
                                if (ri != -1) {
                                  final opt = _reviews[ri];
                                  final merged =
                                      _reviewRowWithToggleLikeReconciled(
                                    updatedReview,
                                    newLikeStatus,
                                    opt,
                                  );
                                  setState(() {
                                    final i2 = _reviews.indexWhere(
                                      (r) => r.id == review.id,
                                    );
                                    if (i2 != -1) {
                                      _reviews[i2] = merged;
                                    }
                                  });
                                  if (_isUsingDefaultReviewQuery) {
                                    ReviewMemoryCache.instance.remember(
                                      _currentProduct.id,
                                      _reviews,
                                    );
                                  }
                                  final uidClear =
                                      _currentUserId?.trim() ??
                                      CurrentUserCache.instance.userId
                                          ?.trim() ??
                                      '';
                                  if (uidClear.isNotEmpty &&
                                      _isMyReview(review) &&
                                      merged.isLikedByCurrentUser) {
                                    await SelfReviewLikeLocalPrefs.instance
                                        .setBoost(uidClear, review.id, false);
                                    if (mounted) {
                                      setState(() {
                                        _selfLikeBoostByReviewId.remove(
                                          review.id,
                                        );
                                      });
                                    }
                                  }
                                }
                              }
                            } on ReviewNotAvailableException {
                              if (reviewIndex != -1 && mounted) {
                                setState(() {
                                  _reviews.removeAt(reviewIndex);
                                  _cachedRatingCounts = null;
                                });
                                ReviewMemoryCache.instance.remember(
                                  _currentProduct.id,
                                  _reviews,
                                );
                                if (context.mounted) {
                                  CustomSnackBar.show(
                                    context,
                                    message:
                                        kMessageReviewNoLongerAvailable,
                                    variant: CustomSnackBarVariant.neutral,
                                  );
                                }
                              }
                            } catch (e) {
                              // Backend'den çekme başarısız olursa, toggle'dan dönen değeri kullan
                              if (reviewIndex != -1) {
                                final currentReview = _reviews[reviewIndex];
                                setState(() {
                                  _reviews[reviewIndex] = ReviewDto(
                                    id: currentReview.id,
                                    title: currentReview.title,
                                    description: currentReview.description,
                                    isCollaborative:
                                        currentReview.isCollaborative,
                                    rating: currentReview.rating,
                                    createdAt: currentReview.createdAt,
                                    productId: currentReview.productId,
                                    productName: currentReview.productName,
                                    ownerId: currentReview.ownerId,
                                    ownerUserName: currentReview.ownerUserName,
                                    ownerProfilePhotoUrl:
                                        currentReview.ownerProfilePhotoUrl,
                                    mediaList: currentReview.mediaList,
                                    likeCount:
                                        newLikeStatus
                                            ? (currentReview.likeCount + 1)
                                            : (currentReview.likeCount > 0
                                                ? currentReview.likeCount - 1
                                                : 0),
                                    isLikedByCurrentUser: newLikeStatus,
                                    isProductNotListed:
                                        currentReview.isProductNotListed,
                                    isReviewInactive:
                                        currentReview.isReviewInactive,
                                  );
                                });
                              }
                            }
                          } catch (e) {
                            if (_isMyReview(review) &&
                                interactionErrorLooksLikeCannotLikeOwnReview(
                                  e,
                                )) {
                              final uid =
                                  _currentUserId?.trim() ??
                                  CurrentUserCache.instance.userId
                                      ?.trim() ??
                                  '';
                              if (uid.isNotEmpty && mounted) {
                                final bNow =
                                    _selfLikeBoostByReviewId[review.id] ==
                                    true;
                                await SelfReviewLikeLocalPrefs.instance
                                    .setBoost(uid, review.id, bNow);
                              }
                            } else {
                              if (_isMyReview(review)) {
                                final uid =
                                    _currentUserId?.trim() ??
                                    CurrentUserCache.instance.userId
                                        ?.trim() ??
                                    '';
                                if (uid.isNotEmpty) {
                                  await SelfReviewLikeLocalPrefs.instance
                                      .setBoost(uid, review.id, boostBeforeTap);
                                }
                                if (mounted) {
                                  setState(() {
                                    if (boostBeforeTap) {
                                      _selfLikeBoostByReviewId[review.id] =
                                          true;
                                    } else {
                                      _selfLikeBoostByReviewId.remove(
                                        review.id,
                                      );
                                    }
                                  });
                                }
                              } else if (reviewIndex != -1) {
                                setState(() {
                                  _reviews[reviewIndex] = review;
                                });
                              }
                              if (context.mounted) {
                                final errorMessage =
                                    ErrorHandler.getUserFriendlyMessage(e);
                                CustomSnackBar.show(
                                  context,
                                  message: errorMessage,
                                  variant: CustomSnackBarVariant.error,
                                );
                              }
                            }
                          }
                          } finally {
                            _reviewListLikeLock.leave(review.id);
                          }
                        },
                      ),
                    );
                    },
                  ),

                const SizedBox(height: AppSpacing.xxLarge),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _miniIconAction({
    IconData? icon,
    Widget? customIcon,
    required VoidCallback? onTap,
    Color? iconColor,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 42),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: customIcon ??
          Icon(
            icon,
            size: 21,
            color: iconColor ?? AppColors.textSecondary,
          ),
    );
  }
}

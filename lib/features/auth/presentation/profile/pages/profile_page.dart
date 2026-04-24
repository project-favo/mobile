import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../../core/cache/app_session_cache.dart';
import '../../../../../core/config/app_background_timers.dart';
import '../../../../../core/cache/product_memory_cache.dart';
import '../../../../../core/cache/review_memory_cache.dart';
import '../../../../../core/cache/profile_warm_cache.dart';
import '../../../../../core/widgets/main_bottom_nav_items.dart';
import '../../../../../features/activity/presentation/activity_page.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/exceptions.dart';
import '../../../../../core/utils/product_listing_flags.dart';
import '../../../../../core/utils/entity_active.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../auth/data/services/auth_service.dart';
import '../../../../auth/data/models/user_response_dto.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/tag_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/services/review_prefetch_service.dart';
import '../../home_page.dart';
import '../../friend_feed_page.dart';
import '../../search_page.dart';
import '../../review/pages/review_detail_page.dart';
import '../../review/pages/review_page.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/widgets/custom_refresh_indicator.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/utils/in_flight_id_lock.dart';
import '../../../../../core/utils/product_report_storage.dart';
import '../../../../../core/utils/app_datetime.dart';
import '../../../../../core/utils/resolve_media_url.dart';
import '../../../../../core/utils/review_report_storage.dart';
import '../../../../../routes/app_routes.dart';
import '../../complete_app_profile_page.dart';
import 'settings_page.dart';
import 'follow_list_page.dart';
import '../widgets/profile_review_row_card.dart';
import '../../review/widgets/review_delete_flow.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final AuthService _authService = AuthService();
  final InteractionRepository _interactionRepository = InteractionRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  final ProductRepository _productRepository = ProductRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  UserResponseDto? _user;
  Uint8List? _cachedProfilePhotoBytes; // build()'da yeniden decode etme — her rebuild'de yeni nesne oluşur ve avatar titrer
  bool _isLoading = true;
  String? _errorMessage;
  List<ProductDto> _wishlistProducts = [];
  List<ProductDto> _wishlistProductsOriginalOrder = [];
  bool _isLoadingWishlist = false;
  String? _wishlistError;
  List<ReviewDto> _myReviews = [];

  /// My Reviews satırlarında ürün görseli için (prefetch).
  final Map<String, ProductDto> _reviewProductHints = {};
  /// GET /api/products/{id} 404/401 — ürün yok/erişim yok (backend review JSON’u işaretlemese bile).
  final Set<String> _unlistedProductIdsFromFailedFetch = {};
  /// [InteractionRepository.isProductReported] — cihaz dışı veya yeni oturum senkronu.
  final Set<String> _productIdsReportedByMeFromServer = {};
  /// [getHomeFeed] ilk sayfada (size 50) yok: vitrin/feed dışı ürün (askı ile uyumlu, görsel+prefetch ile birleşince güvenilir).
  final Set<String> _myReviewProductIdsNotOnHomeFirstPage = {};
  bool _isLoadingMyReviews = false;
  String? _myReviewsError;
  String _selectedDateSort = 'Newest';
  int _followerCount = 0;
  int _followingCount = 0;
  /// Takip / yorum / wishlist: arka planda 5 sn’de bir; çek-refresh ayrı
  Timer? _profilePollTimer;
  bool _profileRefreshInFlight = false;
  final InFlightIdLock _wishlistProductLikeLock = InFlightIdLock();
  final InFlightIdLock _myReviewDeleteLock = InFlightIdLock();

  void _rememberWarmProfile() {
    if (_user == null) return;
    ProfileWarmCache.instance.remember(
      user: _user!,
      myReviews: _myReviews,
      wishlist: _wishlistProducts,
      reviewProductHints: _reviewProductHints,
      followerCount: _followerCount,
      followingCount: _followingCount,
    );
  }

  Route _noAnimationRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  BottomNavigationBar _buildBottomNavigationBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 4,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      selectedFontSize: 0,
      unselectedFontSize: 0,
      onTap: (index) {
        if (index == 4) return;
        if (index == 1) {
          Navigator.pushReplacement(
            context,
            _noAnimationRoute(const FriendFeedPage()),
          );
          return;
        }
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            _noAnimationRoute(const SearchPage()),
          );
          return;
        }
        if (index == 2) {
          Navigator.pushReplacement(
            context,
            _noAnimationRoute(const HomePage()),
          );
          return;
        }
        if (index == 3) {
          Navigator.pushReplacement(
            context,
            _noAnimationRoute(const ActivityPage()),
          );
          return;
        }
      },
      items: MainBottomNavItems.barItems,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(ReviewReportStorage.hydrateForCurrentUser());
    WidgetsBinding.instance.addObserver(this);
    unawaited(ProductReportStorage.hydrateForCurrentUser());
    _tabController = TabController(length: 2, vsync: this);
    final warm = ProfileWarmCache.instance.peek();
    if (warm != null) {
      _user = warm.user;
      _cachedProfilePhotoBytes = decodeProfilePhotoBytes(warm.user.profilePhotoData);
      _myReviews = List<ReviewDto>.from(warm.myReviews);
      _wishlistProducts = List<ProductDto>.from(warm.wishlist);
      _wishlistProductsOriginalOrder = List<ProductDto>.from(warm.wishlist);
      _reviewProductHints.addAll(warm.reviewProductHints);
      _followerCount = warm.followerCount;
      _followingCount = warm.followingCount;
      _isLoading = false;
      // My Reviews: zenginleştirme bitene kadar iskelet — "önce normal sonra askı" titremesin
      _isLoadingMyReviews = true;
      _isLoadingWishlist = false;
      _sortMyReviews();
      _sortWishlist();
      // Sıcak önbellek varken _loadUserData atla — getMe() avatar titremeye neden oluyor.
      // Sadece follower sayılarını ve içerikleri arka planda tazele.
      if (warm.user.id.isNotEmpty) {
        unawaited(_loadFollowCounts(warm.user.id));
      }
      unawaited(
        _loadMyReviews(
          background: true,
          refreshProductState: true,
          waitForEnrichment: true,
        ),
      );
      unawaited(_loadWishlist(background: true));
      unawaited(_revalidateMeOnWarmProfileCache());
    } else {
      _loadUserData();
      // Profil açılır açılmaz My Reviews'ı yükle (ilk sekme)
      _loadMyReviews();
    }
    _profilePollTimer = Timer.periodic(
      AppBackgroundTimers.standardListPoll,
      (_) => unawaited(_pollProfileData()),
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1 &&
          _wishlistProducts.isEmpty &&
          !_isLoadingWishlist) {
        _loadWishlist();
      }
      setState(() {});
    });
  }

  /// [refreshProductState] true: aşağı çek; ipuçları + [ProductMemoryCache] setState’te temizlenir, sonra
  /// tek pasotta zenginleştirme taze sinyal uygular.
  /// [waitForEnrichment] true: prefetch + ana sayfa + reported bitene kadar iskelet (ilk açılış / pull titremesin).
  /// Arka plan (5 sn poll): parça parça setState olmadan tek birleşik zenginleştirme — eski [ProductDto]
  /// (vitrin dışı + eski URL) askıyı tespit etmeyi geciktirmesin.
  Future<void> _loadMyReviews({
    bool background = false,
    bool refreshProductState = false,
    bool waitForEnrichment = false,
  }) async {
    final blockFirstPaint = !background || waitForEnrichment;

    if (!background) {
      setState(() {
        _isLoadingMyReviews = true;
        _myReviewsError = null;
      });
    } else {
      _myReviewsError = null;
    }

    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Please log in to see your reviews.');
      }

      final reviews = await _reviewRepository.getMyReviews(token);
      if (!mounted) return;

      if (blockFirstPaint) {
        final pids =
            reviews.map((r) => r.productId).where((s) => s.isNotEmpty).toSet();
        for (final id in pids) {
          _reviewProductHints.remove(id);
          ProductMemoryCache.instance.remove(id);
        }
        _unlistedProductIdsFromFailedFetch.clear();
        _myReviewProductIdsNotOnHomeFirstPage.clear();
        _productIdsReportedByMeFromServer.clear();

        final enrich = await _enrichMyReviewsData(reviews, token);
        if (!mounted) return;
        setState(() {
          _myReviews = _orderMyReviewsList(reviews);
          _isLoadingMyReviews = false;
          for (final e in enrich.hints.entries) {
            _reviewProductHints[e.key] = e.value;
          }
          _unlistedProductIdsFromFailedFetch.addAll(enrich.unlisted404);
          _myReviewProductIdsNotOnHomeFirstPage
            ..clear()
            ..addAll(enrich.notOnHome);
          _productIdsReportedByMeFromServer
            ..clear()
            ..addAll(enrich.reportedIds);
        });
        _rememberWarmProfile();
        return;
      }

      setState(() {
        _myReviews = reviews;
        _isLoadingMyReviews = false;
        final pids =
            reviews.map((r) => r.productId).where((s) => s.isNotEmpty).toSet();
        if (!background || refreshProductState) {
          for (final id in pids) {
            _reviewProductHints.remove(id);
            ProductMemoryCache.instance.remove(id);
          }
          _unlistedProductIdsFromFailedFetch.clear();
          _myReviewProductIdsNotOnHomeFirstPage.clear();
          _productIdsReportedByMeFromServer.clear();
        } else {
          _reviewProductHints.removeWhere((k, _) => !pids.contains(k));
        }
      });
      _rememberWarmProfile();
      _sortMyReviews();
      unawaited(_reconcileMyReviewsEnrichment(reviews, token));
    } catch (e) {
      if (mounted) {
        if (background && _myReviews.isNotEmpty) {
          _isLoadingMyReviews = false;
          return;
        }
        setState(() {
          _myReviewsError = ErrorHandler.getUserFriendlyMessage(e);
          _isLoadingMyReviews = false;
        });
      }
    }
  }

  List<ReviewDto> _orderMyReviewsList(List<ReviewDto> source) {
    if (source.isEmpty) return source;
    final sorted = List<ReviewDto>.from(source);
    sorted.sort((a, b) {
      final da =
          parseBackendDateTimeToLocal(a.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db =
          parseBackendDateTimeToLocal(b.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (_selectedDateSort == 'Newest') {
        return db.compareTo(da);
      }
      return da.compareTo(db);
    });
    return sorted;
  }

  Future<({
    Map<String, ProductDto> hints,
    Set<String> unlisted404,
    Set<String> notOnHome,
    Set<String> reportedIds,
  })> _enrichMyReviewsData(
    List<ReviewDto> reviews,
    String token,
  ) async {
    final w = await Future.wait<dynamic>([
      _prefetchProductHintsData(reviews, token),
      _syncNotOnHomeFirstPageData(reviews, token),
      _syncMyReportedProductFlagsData(reviews, token),
    ]);
    final pre = w[0] as ({Map<String, ProductDto> hints, Set<String> unlisted404});
    return (
      hints: pre.hints,
      unlisted404: pre.unlisted404,
      notOnHome: w[1] as Set<String>,
      reportedIds: w[2] as Set<String>,
    );
  }

  Future<({Map<String, ProductDto> hints, Set<String> unlisted404})>
  _prefetchProductHintsData(
    List<ReviewDto> reviews,
    String token,
  ) async {
    final ids =
        reviews.map((r) => r.productId).where((s) => s.isNotEmpty).toSet();
    final hints = <String, ProductDto>{};
    final unlisted404 = <String>{};
    if (ids.isEmpty) {
      return (hints: hints, unlisted404: unlisted404);
    }
    final list = ids.toList();
    const batchSize = 5;
    for (var i = 0; i < list.length; i += batchSize) {
      final end = (i + batchSize > list.length) ? list.length : i + batchSize;
      final slice = list.sublist(i, end);
      final results = await Future.wait(
        slice.map((id) async {
          try {
            return MapEntry(
              id,
              await _productRepository.getProductById(
                id,
                firebaseIdToken: token,
                bypassCache: true,
              ),
            );
          } on ProductNotAvailableException {
            return MapEntry<String, ProductDto?>(id, null);
          } catch (_) {
            return null;
          }
        }),
      );
      for (final e in results) {
        if (e == null) continue;
        if (e.value == null) {
          unlisted404.add(e.key);
        } else {
          hints[e.key] = e.value!;
        }
      }
    }
    return (hints: hints, unlisted404: unlisted404);
  }

  Future<Set<String>> _syncNotOnHomeFirstPageData(
    List<ReviewDto> reviews,
    String token,
  ) async {
    final mine =
        reviews.map((r) => r.productId.trim()).where((s) => s.isNotEmpty).toSet();
    if (mine.isEmpty) return {};
    try {
      final feed = await _productRepository.getHomeFeed(
        page: 0,
        size: 50,
        firebaseIdToken: token,
      );
      final onHome = feed.content.map((e) => e.id.trim()).toSet();
      return mine.where((id) => !onHome.contains(id)).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _syncMyReportedProductFlagsData(
    List<ReviewDto> reviews,
    String token,
  ) async {
    final ids =
        reviews.map((r) => r.productId).where((s) => s.isNotEmpty).toSet();
    if (ids.isEmpty) return {};
    final list = ids.toList();
    const batch = 5;
    final fromApi = <String>{};
    for (var i = 0; i < list.length; i += batch) {
      final j = i + batch > list.length ? list.length : i + batch;
      final slice = list.sublist(i, j);
      final rows = await Future.wait(
        slice.map(
          (id) async {
            final ok = await _interactionRepository.isProductReported(
              token,
              id,
            );
            return MapEntry(id, ok);
          },
        ),
      );
      for (final e in rows) {
        if (e.value) fromApi.add(e.key);
      }
    }
    return fromApi;
  }

  /// Arka planda (5 sn poll vb.) tüm sinyalleri aynı anda türet; önce [setState] ile
  /// ayrı ayrı güncellemek eski [ProductDto] (ör. vitrinde artık yok) ile askıyı
  /// tespit etmeyi geciktiriyordu — tek [setState] ile taze hali uygular.
  Future<void> _reconcileMyReviewsEnrichment(
    List<ReviewDto> reviews,
    String token,
  ) async {
    final pids =
        reviews.map((r) => r.productId).where((s) => s.isNotEmpty).toSet();
    if (pids.isEmpty) return;
    final enrich = await _enrichMyReviewsData(reviews, token);
    if (!mounted) return;
    setState(() {
      for (final id in pids) {
        _reviewProductHints.remove(id);
        ProductMemoryCache.instance.remove(id);
      }
      for (final e in enrich.hints.entries) {
        if (pids.contains(e.key)) {
          _reviewProductHints[e.key] = e.value;
        }
      }
      _unlistedProductIdsFromFailedFetch
        ..removeWhere((id) => pids.contains(id))
        ..addAll(enrich.unlisted404);
      _myReviewProductIdsNotOnHomeFirstPage
        ..removeWhere((id) => pids.contains(id))
        ..addAll(enrich.notOnHome);
      for (final id in pids) {
        if (enrich.reportedIds.contains(id)) {
          _productIdsReportedByMeFromServer.add(id);
        } else {
          _productIdsReportedByMeFromServer.remove(id);
        }
      }
    });
    _rememberWarmProfile();
  }

  bool _isMyReviewRowNotListed(ReviewDto review, ProductDto? hint) {
    if (!isReviewEntityVisible(review)) return true;
    if (review.isProductNotListed) return true;
    if (hint?.isProductNotListed == true) return true;
    if (_unlistedProductIdsFromFailedFetch.contains(review.productId)) {
      return true;
    }
    // Sunucu vitrin dışı ürünü 200 dönüp imageURL boş bırakabiliyor; yoksa ağ bayraklarını anlamıyoruz
    if (hint != null &&
        isNotListedImpliedByEmptyProductImage(hint.imageURL)) {
      return true;
    }
    // Ana sayfada (ilk 50) yok + görsel yok/prefetch yok: askıdaki ürün tipik örüntü
    if (_myReviewProductIdsNotOnHomeFirstPage.contains(
          review.productId,
        ) &&
        (hint == null ||
            isNotListedImpliedByEmptyProductImage(hint.imageURL))) {
      return true;
    }
    return false;
  }

  /// [ProductDto] askı/404/home sinyali ile vitrin dışı kalan yorumlar My Reviews’da listelenmez.
  List<ReviewDto> _myReviewsVisibleInTab() {
    return _myReviews.where((r) {
      final hint = _reviewProductHints[r.productId];
      return !_isMyReviewRowNotListed(r, hint);
    }).toList();
  }

  String _myReviewsAverageLabel() {
    final visible = _myReviewsVisibleInTab();
    if (visible.isEmpty) return '—';
    final sum = visible.fold<double>(0, (a, r) => a + r.rating);
    return (sum / visible.length).toStringAsFixed(1);
  }

  ProductDto _productForReviewDetail(ReviewDto review, ProductDto? hint) {
    if (hint != null) return hint;
    return ProductDto(
      id: review.productId,
      name: review.productName,
      imageURL: '',
      description: null,
      tag: TagDto(id: '', name: ''),
      isProductNotListed: review.isProductNotListed,
    );
  }

  Future<void> _onDeleteMyReview(ReviewDto review) async {
    if (!_myReviewDeleteLock.tryEnter(review.id)) return;
    try {
      final ok = await ReviewDeleteFlow.confirmAndDelete(
        context,
        repository: _reviewRepository,
        sessionHelper: _sessionHelper,
        reviewId: review.id,
      );
      if (!mounted || !ok) return;
      setState(() {
        _myReviews.removeWhere((r) => r.id == review.id);
      });
      ReviewMemoryCache.instance.removeReviewFromProduct(
        review.productId,
        review.id,
      );
      _rememberWarmProfile();
    } finally {
      _myReviewDeleteLock.leave(review.id);
    }
  }

  Widget _buildMyReviewsTab() {
    if (_isLoadingMyReviews) {
      return Column(
        children: [
          const ReviewCardSkeleton(),
          const SizedBox(height: AppSpacing.medium),
          const ReviewCardSkeleton(),
          const SizedBox(height: AppSpacing.medium),
          const ReviewCardSkeleton(),
        ],
      );
    }
    if (_myReviewsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _myReviewsError!,
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.large),
              TextButton(onPressed: _loadMyReviews, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final visibleMyReviews = _myReviewsVisibleInTab();
    if (visibleMyReviews.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xLarge),
          child: Text('No reviews yet', style: AppTextStyles.bodySecondary),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
      itemCount: visibleMyReviews.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.medium),
      itemBuilder: (context, index) {
        final review = visibleMyReviews[index];
        final hint = _reviewProductHints[review.productId];
        final youReportedReview = ReviewReportStorage.hasReportedSync(
          review.id,
        );
        final youReportedProduct =
            ProductReportStorage.hasReportedSync(review.productId) ||
            _productIdsReportedByMeFromServer.contains(review.productId);
        return ProfileReviewRowCard(
          key: ValueKey(review.id),
          review: review,
          productImageUrl: hint?.imageURL,
          youReportedThisReview: youReportedReview,
          youReportedThisProduct: youReportedProduct,
          onDelete: () => _onDeleteMyReview(review),
          onTap: () async {
            final cached =
                ProductMemoryCache.instance.peek(review.productId) ??
                _reviewProductHints[review.productId];
            final product = _productForReviewDetail(review, cached);
            final result = await Navigator.push<dynamic>(
              context,
              SlideRightRoute(
                page: ReviewDetailPage(
                  review: review,
                  product: product,
                ),
              ),
            );
            if (!mounted) return;
            if (result == ReviewDeleteFlow.popResultDeleted) {
              setState(() {
                _myReviews.removeWhere((r) => r.id == review.id);
              });
              ReviewMemoryCache.instance.removeReviewFromProduct(
                review.productId,
                review.id,
              );
              _rememberWarmProfile();
            }
          },
        );
      },
    );
  }

  /// Sıcak önbellekle açılışta [getMe] atlanabiliyor; kapatılmış hesabı tespit etmek için arka planda doğrular.
  Future<void> _revalidateMeOnWarmProfileCache() async {
    try {
      await _authService.getMe();
    } on DeactivatedAccountException {
      // [SessionHelper.handleDeactivatedAccount] oturumu kapatır ve girişe yönlendirir
    } catch (_) {}
  }

  Future<void> _loadUserData({bool background = false}) async {
    if (!background) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      _errorMessage = null;
    }

    try {
      // Background modda token sync atla — yavaş ve avatar flicker'a sebep oluyor
      if (!background) {
        await _authService.syncFirebaseUserAndRefreshIdToken();
      }
      var user = await _authService.getMe();
      if (!user.hasProfileAvatarVisual && user.id.isNotEmpty) {
        final extra = await _authService.getUserById(user.id);
        user = user.withFilledAvatarFrom(extra);
      }
      if (!mounted) return;
      setState(() {
        _user = user;
        _cachedProfilePhotoBytes = decodeProfilePhotoBytes(user.profilePhotoData);
        _isLoading = false;
        if (user.id.isEmpty) {
          _followerCount = 0;
          _followingCount = 0;
        }
      });
      _rememberWarmProfile();
      if (user.id.isNotEmpty) {
        unawaited(_loadFollowCounts(user.id));
      }
    } on DeactivatedAccountException {
      if (!mounted) return;
    } catch (e) {
      if (background && _user != null) {
        _isLoading = false;
        return;
      }
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _signOutFromIncompleteProfile() async {
    AuthService.clearRegisterFormDraft();
    _sessionHelper.clearSession();
    clearAllAppCachesOnLogout();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  Future<void> _loadFollowCounts(String userId) async {
    final results = await Future.wait([
      _interactionRepository.countVisibleFollowers(userId),
      _interactionRepository.countVisibleFollowing(userId),
    ]);
    if (!mounted) return;
    setState(() {
      _followerCount = results[0];
      _followingCount = results[1];
    });
  }

  /// Takip / takipçi listesinden dönünce sayıları tazele.
  Future<void> _openFollowListAndRefresh({required bool isFollowers}) async {
    if (_user == null || _user!.id.isEmpty) return;
    final id = _user!.id;
    await Navigator.push<void>(
      context,
      SlideRightRoute(
        page: FollowListPage(
          userId: id,
          title: isFollowers ? 'Followers' : 'Following',
          isFollowers: isFollowers,
        ),
      ),
    );
    if (!mounted) return;
    await _loadFollowCounts(id);
  }

  /// Sunucu: takip sayıları + yorumlar (suspend / ortalama) + wishlist; getMe yok (avatar titremesin).
  Future<void> _pollProfileData() async {
    if (!mounted) return;
    if (_isLoading) return;
    if (_user == null || _user!.id.isEmpty) return;
    if (_profileRefreshInFlight) return;
    _profileRefreshInFlight = true;
    try {
      await _loadUserData(background: true);
      if (!mounted) return;
      if (_user == null || _user!.id.isEmpty) return;
      final id = _user!.id;
      await Future.wait<void>([
        _loadFollowCounts(id),
        _loadMyReviews(background: true),
        _loadWishlist(background: true),
      ]);
    } catch (_) {
    } finally {
      _profileRefreshInFlight = false;
    }
  }

  /// Aşağı çek: getMe + yorum + wishlist (avatar/kullanıcı alanı da güncellenir)
  Future<void> _onProfilePullToRefresh() async {
    if (!mounted) return;
    if (_user == null || _user!.id.isEmpty) return;
    try {
      await _loadUserData(background: true);
      if (!mounted) return;
      if (_user?.id == null || _user!.id.isEmpty) return;
      await Future.wait<void>([
        _loadMyReviews(
          background: true,
          refreshProductState: true,
          waitForEnrichment: true,
        ),
        _loadWishlist(background: true),
      ]);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profilePollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadUserData(background: true));
    }
  }

  /// Wishlist [ProductDto] satırını [getProductById] ile teyit eder; askı/404’te [null] (satır gider).
  Future<ProductDto?> _revalidateWishlistRow(
    ProductDto p,
    String token,
  ) async {
    if (p.isProductNotListed || isNotListedImpliedByEmptyProductImage(p.imageURL)) {
      return null;
    }
    try {
      final fresh = await _productRepository.getProductById(
        p.id,
        firebaseIdToken: token,
        bypassCache: true,
      );
      if (fresh.isProductNotListed ||
          isNotListedImpliedByEmptyProductImage(fresh.imageURL)) {
        return null;
      }
      final at = p.createdAt;
      if (at != null) {
        return fresh.copyWith(createdAt: at);
      }
      return fresh;
    } on ProductNotAvailableException {
      return null;
    } catch (_) {
      return p;
    }
  }

  /// [getMyWishlist] cevabını vitrin/askı ile hizala (5 sn poll + ilk yükleme).
  Future<List<ProductDto>> _filterWishlistToListedProducts(
    List<ProductDto> fromServer,
    String token,
  ) async {
    if (fromServer.isEmpty) return const [];
    final out = <ProductDto>[];
    const batch = 5;
    for (var i = 0; i < fromServer.length; i += batch) {
      if (!mounted) return out;
      final end = (i + batch) > fromServer.length ? fromServer.length : (i + batch);
      final slice = fromServer.sublist(i, end);
      final part = await Future.wait(
        slice.map((p) => _revalidateWishlistRow(p, token)),
      );
      for (final q in part) {
        if (q != null) out.add(q);
      }
    }
    return out;
  }

  Future<void> _loadWishlist({bool background = false}) async {
    if (!background) {
      setState(() {
        _isLoadingWishlist = true;
        _wishlistError = null;
      });
    } else {
      _wishlistError = null;
    }

    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      final raw = await _interactionRepository.getMyWishlist(token);
      if (!mounted) return;
      final products = await _filterWishlistToListedProducts(raw, token);
      if (!mounted) return;
      setState(() {
        _wishlistProducts = List.from(products);
        _wishlistProductsOriginalOrder = List.from(products);
        _isLoadingWishlist = false;
      });
      _rememberWarmProfile();
      ReviewPrefetchService.instance.prefetchForProducts(
        products,
        maxCount: 6,
      );
      for (final p in products) {
        ProductMemoryCache.instance.remember(p);
      }
      _sortWishlist();
    } catch (e) {
      if (!mounted) return;
      if (background && _wishlistProducts.isNotEmpty) {
        _isLoadingWishlist = false;
        return;
      }
      setState(() {
        _wishlistError = ErrorHandler.getUserFriendlyMessage(e);
        _isLoadingWishlist = false;
      });
    }
  }

  Widget _buildWishlistTab() {
    if (_isLoadingWishlist) {
      return Column(
        children: [
          const ProductCardSkeleton(),
          const SizedBox(height: AppSpacing.large),
          const ProductCardSkeleton(),
        ],
      );
    }
    if (_wishlistError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Text(
            _wishlistError!,
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_wishlistProducts.isEmpty) {
      return const Center(
        child: Text(
          'Your wishlist is empty.',
          style: AppTextStyles.bodySecondary,
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
      itemCount: _wishlistProducts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final product = _wishlistProducts[index];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _WishlistRow(
            key: ValueKey(product.id),
            product: product,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ReviewPage(product: product)),
            ),
            onFavoriteTap: () => _toggleWishlistLike(product),
          ),
        );
      },
    );
  }

  Future<void> _toggleWishlistLike(ProductDto product) async {
    if (!_wishlistProductLikeLock.tryEnter(product.id)) return;
    final index = _wishlistProducts.indexWhere((p) => p.id == product.id);
    if (index == -1) {
      _wishlistProductLikeLock.leave(product.id);
      return;
    }

    final previous = _wishlistProducts[index];

    // Optimistic update
    setState(() {
      _wishlistProducts[index] = previous.copyWith(
        isLiked: !(previous.isLiked ?? true),
      );
    });

    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      final liked = await _interactionRepository.toggleProductLike(
        token,
        product.id,
      );

      if (!mounted) return;
      setState(() {
        if (!liked) {
          _wishlistProducts.removeWhere((p) => p.id == product.id);
          _wishlistProductsOriginalOrder.removeWhere((p) => p.id == product.id);
        } else {
          // Hâlâ likelıysa durumu güncelle
          final idx = _wishlistProducts.indexWhere((p) => p.id == product.id);
          if (idx != -1) {
            _wishlistProducts[idx] = _wishlistProducts[idx].copyWith(
              isLiked: liked,
            );
          }
        }
      });
    } catch (e) {
      // Hata durumunda önceki haline dön
      if (!mounted) return;
      setState(() {
        final idx = _wishlistProducts.indexWhere((p) => p.id == previous.id);
        if (idx != -1) {
          _wishlistProducts[idx] = previous;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getUserFriendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      _wishlistProductLikeLock.leave(product.id);
    }
  }

  void _sortWishlist() {
    if (_wishlistProducts.isEmpty) return;

    final hasAnyDate = _wishlistProducts.any((p) => p.createdAt != null);
    if (hasAnyDate) {
      final sorted = List<ProductDto>.from(_wishlistProducts);
      sorted.sort((a, b) {
        final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (_selectedDateSort == 'Newest') {
          return db.compareTo(da);
        }
        return da.compareTo(db);
      });
      _wishlistProducts = sorted;
    } else {
      if (_selectedDateSort == 'Newest') {
        _wishlistProducts = List.from(_wishlistProductsOriginalOrder);
      } else {
        _wishlistProducts = _wishlistProductsOriginalOrder.reversed.toList();
      }
    }
    setState(() {});
  }

  void _sortMyReviews() {
    if (_myReviews.isEmpty) return;
    final sorted = List<ReviewDto>.from(_myReviews);
    sorted.sort((a, b) {
      final da =
          parseBackendDateTimeToLocal(a.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db =
          parseBackendDateTimeToLocal(b.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (_selectedDateSort == 'Newest') {
        return db.compareTo(da);
      }
      return da.compareTo(db);
    });
    _myReviews = sorted;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Profile', style: AppTextStyles.HomeHeader),
          centerTitle: true,
        ),
        body: const _ProfilePageSkeleton(),
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    if (_errorMessage != null || _user == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Profile', style: AppTextStyles.HomeHeader),
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage ?? 'Failed to load user data',
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.large),
              ElevatedButton(
                onPressed: _loadUserData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    if (_user != null && _user!.id.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Profile', style: AppTextStyles.HomeHeader),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxLarge),
                Icon(
                  Icons.verified_user_outlined,
                  size: 56,
                  color: AppColors.primary.withValues(alpha: 0.85),
                ),
                const SizedBox(height: AppSpacing.xLarge),
                Text(
                  'Complete your profile',
                  style: AppTextStyles.heading2.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.medium),
                Text(
                  'If your registration info was saved, it will be prefilled on '
                  '"Complete profile". In some cases, the server may expose your '
                  'user id a bit later, but you might still need to complete this step once.',
                  style: AppTextStyles.bodySecondary,
                  textAlign: TextAlign.center,
                ),
                if (_user!.email.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.large),
                  Text(
                    _user!.email,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (!(_user!.isEmailVerified)) ...[
                  const SizedBox(height: AppSpacing.medium),
                  Text(
                    'Email verification pending. Open the link in your inbox.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
                AppButton(
                  text: 'Complete profile',
                  onPressed: () async {
                    final ok = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CompleteAppProfilePage(),
                      ),
                    );
                    if (ok == true && mounted) {
                      await _loadUserData();
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                TextButton(
                  onPressed: _signOutFromIncompleteProfile,
                  child: Text(
                    'Sign out',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxLarge),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Profile', style: AppTextStyles.HomeHeader),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            color: AppColors.primary,
            onPressed: () async {
              final result = await Navigator.push<dynamic>(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(initialUser: _user),
                ),
              );
              if (!mounted) return;
              if (result is UserResponseDto) {
                setState(() {
                  _user = result;
                  _cachedProfilePhotoBytes = result.hasProfileAvatarVisual
                      ? decodeProfilePhotoBytes(result.profilePhotoData)
                      : null;
                });
                _rememberWarmProfile();
              } else if (result == true) {
                unawaited(_loadUserData(background: true));
              }
            },
          ),
        ],
      ),
      body: CustomRefreshIndicator(
        onRefresh: _onProfilePullToRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
            const SizedBox(height: AppSpacing.xxLarge),
            ProfileAvatar(
              radius: 50,
              imageUrl: _user!.profileImageUrl,
              memoryBytes: _cachedProfilePhotoBytes,
              fallbackInitial: _user!.userName,
            ),
            const SizedBox(height: AppSpacing.large),
            if (_user!.name != null || _user!.surname != null) ...[
              Text(
                '${_user!.name ?? ''} ${_user!.surname ?? ''}'.trim(),
                style: AppTextStyles.titleMedium,
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                '@${_user!.userName.replaceAll(' ', '')}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ] else ...[
              Text(
                '@${_user!.userName.replaceAll(' ', '')}',
                style: AppTextStyles.titleMedium,
              ),
            ],
            const SizedBox(height: AppSpacing.xxLarge),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.medium,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => unawaited(
                        _openFollowListAndRefresh(isFollowers: true),
                      ),
                      child: _StatItem(
                        count: _followerCount,
                        label: 'Followers',
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => unawaited(
                        _openFollowListAndRefresh(isFollowers: false),
                      ),
                      child: _StatItem(
                        count: _followingCount,
                        label: 'Following',
                      ),
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      count: _myReviewsVisibleInTab().length,
                      label: 'Reviews',
                    ),
                  ),
                  Expanded(
                    child: Tooltip(
                      message:
                          'Average star rating of your reviews (out of 5).',
                      child: _StatTextItem(
                        value: _myReviewsAverageLabel(),
                        label: 'Review avg',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxLarge),
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                tabs: const [Tab(text: 'My Reviews'), Tab(text: 'Wishlist')],
              ),
            ),
            const SizedBox(height: AppSpacing.large),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xLarge,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Sort by date',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  _SortDropdown(
                    items: const ['Newest', 'Oldest'],
                    value: _selectedDateSort,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedDateSort = value);
                      if (_tabController.index == 0) {
                        _sortMyReviews();
                      } else {
                        _sortWishlist();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxLarge),
            if (_tabController.index == 0)
              _buildMyReviewsTab()
            else
              _buildWishlistTab(),
            const SizedBox(height: AppSpacing.xxLarge),
          ],
        ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}

/// Ana profil verisi yüklenirken gerçek düzenle uyumlu shimmer.
class _ProfilePageSkeleton extends StatelessWidget {
  const _ProfilePageSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xxLarge),
          ClipOval(
            child: SkeletonLoader(
              width: 100,
              height: 100,
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          SkeletonLoader(
            width: 200,
            height: 22,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: AppSpacing.small),
          SkeletonLoader(
            width: 140,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: AppSpacing.xxLarge),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
            child: Row(
              children: [
                Expanded(child: _profileStatSkeleton()),
                Expanded(child: _profileStatSkeleton()),
                Expanded(child: _profileStatSkeleton()),
                Expanded(child: _profileStatSkeleton()),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxLarge),
          LayoutBuilder(
            builder: (context, c) {
              return SkeletonLoader(
                width: c.maxWidth,
                height: 46,
                borderRadius: BorderRadius.circular(14),
              );
            },
          ),
          const SizedBox(height: AppSpacing.large),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonLoader(
                  width: 100,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
                SkeletonLoader(
                  width: 88,
                  height: 32,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxLarge),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
            child: Column(
              children: [
                const ReviewCardSkeleton(),
                const SizedBox(height: AppSpacing.medium),
                const ReviewCardSkeleton(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxLarge),
        ],
      ),
    );
  }

  static Widget _profileStatSkeleton() {
    return Column(
      children: [
        SkeletonLoader(
          width: 36,
          height: 24,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: AppSpacing.small),
        SkeletonLoader(
          width: 64,
          height: 12,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;

  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: AppTextStyles.heading3,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.small),
        Text(
          label,
          style: AppTextStyles.bodySecondary,
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }
}

class _StatTextItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatTextItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: AppTextStyles.heading3, maxLines: 1),
        ),
        const SizedBox(height: AppSpacing.small),
        Text(
          label,
          style: AppTextStyles.bodySecondary,
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final List<String> items;
  final String value;
  final ValueChanged<String?> onChanged;

  const _SortDropdown({
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        alignment: AlignmentDirectional.centerEnd,
        borderRadius: BorderRadius.circular(10),
        iconSize: 18,
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        items: items.map((String item) {
          return DropdownMenuItem<String>(value: item, child: Text(item));
        }).toList(),
        onChanged: onChanged,
        icon: const Icon(
          Icons.expand_more_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ─── Wishlist satır kartı ─────────────────────────────────────────────────────

class _WishlistRow extends StatelessWidget {
  final ProductDto product;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const _WishlistRow({
    super.key,
    required this.product,
    required this.onTap,
    required this.onFavoriteTap,
  });

  @override
  Widget build(BuildContext context) {
    final liked = product.isLiked ?? true;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Ürün görseli
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                product.imageURL,
                width: 68,
                height: 68,
                fit: BoxFit.cover,
                cacheWidth: 136,
                cacheHeight: 136,
                errorBuilder: (_, __, ___) => Container(
                  width: 68,
                  height: 68,
                  color: AppColors.border,
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    size: 24,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // İsim + kategori
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.tag.name,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Like butonu — ProductCard ile aynı stil
            GestureDetector(
              onTap: onFavoriteTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: 22,
                  color: liked ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

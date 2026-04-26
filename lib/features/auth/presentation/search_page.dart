import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/cache/current_user_cache.dart';
import '../../../core/cache/following_id_set_cache.dart';
import '../../../core/cache/search_warm_cache.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/session_helper.dart';
import '../../../core/utils/user_profile_navigation.dart';
import '../../../core/utils/entity_active.dart';
import '../../../core/notifications/notification_realtime_service.dart';
import '../../../core/widgets/main_bottom_nav_items.dart';
import '../../../features/activity/presentation/activity_page.dart';
import '../data/models/product_dto.dart';
import '../data/models/conversation_dto.dart';
import '../data/models/review_dto.dart';
import '../data/models/tag_dto.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/review_repository.dart';
import '../data/repositories/interaction_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/services/auth_service.dart';
import '../data/services/review_prefetch_service.dart';
import '../widgets/product_card.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/custom_snack_bar.dart';
import '../../../core/widgets/profile_avatar.dart';
import 'home_page.dart';
import 'friend_feed_page.dart';
import 'profile/pages/profile_page.dart';
import 'review/pages/review_page.dart';
import 'review/review_page_pop_result.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const Duration _topReviewersRefreshInterval = Duration(seconds: 10);
  final ProductRepository _productRepository = ProductRepository();
  final TagRepository _tagRepository = TagRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  final InteractionRepository _interactionRepository = InteractionRepository();
  final AuthService _authService = AuthService();
  final SessionHelper _sessionHelper = SessionHelper();
  final Map<String, int> _productCardResync = {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<ProductDto> _allProducts = [];
  List<ProductDto> _searchResults = [];
  List<TagDto> _rootCategories = [];
  List<TagDto> _currentCategories = [];
  final List<List<TagDto>> _categoryHistory = [];
  final List<TagDto> _categoryPath = [];
  TagDto? _activeLeafCategory;
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isLoadingCategories = false;
  bool _showCategoryResults = false;
  String? _errorMessage;
  String _activeQuery = '';
  String? _firebaseIdToken;
  bool _notificationSvcAttached = false;
  Timer? _topReviewersRefreshTimer;
  Timer? _searchDebounce;
  Timer? _userSearchDebounce;
  String? _currentUserId;
  final Set<String> _productLikeInFlight = <String>{};
  final Set<String> _socialCountsInFlight = <String>{};

  /// GET /api/reviews/top-reviewers — giriş yapmışken dolar
  List<TopReviewerDto> _topReviewers = [];
  bool _loadingTopReviewers = false;

  /// Takip / takipçi (arama havuzu — giriş gerekir)
  List<ConversationUserDto> _socialSearchUsers = [];

  /// Aktif sorgu için eşleşen profiller (kullanıcı adı metni)
  List<_ProfileSearchEntry> _profileSearchMatches = [];

  /// Sayfa açılınca arka planda preload edilen tüm kullanıcı dizini.
  /// Arama anında bu listeden filtrelenir → sıfır network gecikmesi.
  List<dynamic> _preloadedUsers = [];

  /// Server search cache: en son server aramasının sonuçları ve query'si.
  List<dynamic> _serverUserResults = [];
  String _serverUserResultsQuery = '';

  Route _noAnimationRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  @override
  void initState() {
    super.initState();
    final warmUserId = CurrentUserCache.instance.userId?.trim();
    if (warmUserId != null && warmUserId.isNotEmpty) {
      _currentUserId = warmUserId;
    }
    unawaited(
      FollowingIdSetCache.instance.ensureLoaded(
        _interactionRepository,
        _authService,
        _sessionHelper,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hookNotificationsIfSignedIn());
    });
    _searchFocusNode.addListener(() {
      setState(() {});
    });
    unawaited(_loadTopReviewers());
    _loadInitialData();
    unawaited(_loadCurrentUserIdentity());
    unawaited(_loadSocialGraphForSearch());
    unawaited(_preloadUserDirectory());
    _scheduleTopReviewerRefresh();
    registerProductCardGridResyncHandler(_onProductCardGridResync);
  }

  Future<void> _loadCurrentUserIdentity() async {
    try {
      final warm = CurrentUserCache.instance.userId?.trim();
      if (warm != null && warm.isNotEmpty && mounted) {
        setState(() {
          _currentUserId = warm;
        });
      }
      final token = await _sessionHelper.ensureSession();
      if (token == null || !mounted) return;
      final me = await _authService.getMe();
      if (!mounted) return;
      setState(() {
        _currentUserId = me.id.trim();
      });
    } catch (e, s) {
      AppLogger.warnSilencedError('SearchPage._loadCurrentUserIdentity', e, s);
    }
  }

  /// Server'dan kullanıcı araması yapar ve sonuçları [_profileSearchMatches]'e ekler.
  Future<void> _searchUsersFromServer(String normalizedQuery) async {
    try {
      final serverUsers = await _authService.searchUsers(normalizedQuery, size: 30);
      if (!mounted || _activeQuery != normalizedQuery) return;
      // Query değişmişse sonuçları yok say.
      if (serverUsers.isEmpty) return;
      _serverUserResults = serverUsers;
      _serverUserResultsQuery = normalizedQuery;
      setState(() {
        _profileSearchMatches = _mergeProfileMatches(normalizedQuery, serverUsers);
      });
    } catch (e, s) {
      AppLogger.warnSilencedError('SearchPage._searchUsersFromServer', e, s);
    }
  }

  /// Server sonuçlarını lokal sonuçlarla birleştirir.
  /// Server sonuçları önce gelir, ardından sadece lokalde bulunanlar eklenir.
  List<_ProfileSearchEntry> _mergeProfileMatches(
    String q,
    List<dynamic> serverUsers,
  ) {
    final seen = <String>{};
    final merged = <_ProfileSearchEntry>[];

    for (final u in serverUsers) {
      final id = u.id.trim();
      final name = u.userName.trim();
      if (id.isEmpty || name.isEmpty) continue;
      if (u.isProfileViewBlocked) continue;
      if (!seen.add(id)) continue;
      merged.add(_ProfileSearchEntry(
        userId: id,
        userName: name,
        profileImageUrl: u.profileImageUrl,
      ));
    }

    for (final e in _computeProfileMatches(q)) {
      if (!seen.add(e.userId)) continue;
      merged.add(e);
    }

    merged.sort((a, b) {
      final an = a.userName.toLowerCase();
      final bn = b.userName.toLowerCase();
      final aStarts = an.startsWith(q) ? 0 : 1;
      final bStarts = bn.startsWith(q) ? 0 : 1;
      if (aStarts != bStarts) return aStarts - bStarts;
      return an.compareTo(bn);
    });

    if (merged.length > 50) return merged.sublist(0, 50);
    return merged;
  }

  /// Profil adına göre yerel eşleşme: top reviewers + takip edilen / takipçi.
  List<_ProfileSearchEntry> _computeProfileMatches(String q) {
    if (q.isEmpty) return const [];
    final seen = <String>{};
    final merged = <_ProfileSearchEntry>[];

    void add(String userId, String userName, String? imageUrl) {
      final id = userId.trim();
      final name = userName.trim();
      if (id.isEmpty || name.isEmpty) return;
      if (!seen.add(id)) return;
      merged.add(
        _ProfileSearchEntry(userId: id, userName: name, profileImageUrl: imageUrl),
      );
    }

    for (final t in _topReviewers) {
      add(t.userId, t.userName, t.profileImageUrl);
    }
    for (final c in _socialSearchUsers) {
      if (c.id <= 0) continue;
      add(c.id.toString(), c.username, c.profilePhotoUrl);
    }

    final out =
        merged.where((e) {
          final n = e.userName.toLowerCase();
          return n.contains(q);
        }).toList()
          ..sort((a, b) {
            final an = a.userName.toLowerCase();
            final bn = b.userName.toLowerCase();
            final aStarts = an.startsWith(q) ? 0 : 1;
            final bStarts = bn.startsWith(q) ? 0 : 1;
            if (aStarts != bStarts) return aStarts - bStarts;
            return an.compareTo(bn);
          });
    if (out.length > 20) return out.sublist(0, 20);
    return out;
  }

  void _recomputeProfileMatchesIfNeeded() {
    if (!mounted) return;
    final q = _activeQuery;
    if (q.isEmpty) {
      if (_profileSearchMatches.isNotEmpty) {
        setState(() => _profileSearchMatches = []);
      }
      return;
    }
    setState(() {
      _profileSearchMatches = _resolveProfileMatches(q);
    });
  }

  Future<void> _loadSocialGraphForSearch() async {
    try {
      final t = await _sessionHelper.ensureSession();
      if (t == null || !mounted) return;
      final me = await _authService.getMe();
      if (!mounted || me.id.trim().isEmpty) return;
      final following = await _interactionRepository.getFollowing(
        me.id,
        page: 0,
        size: 100,
      );
      final followers = await _interactionRepository.getFollowers(
        me.id,
        page: 0,
        size: 100,
      );
      if (!mounted) return;
      final byId = <int, ConversationUserDto>{};
      for (final u in following) {
        if (u.id > 0) {
          byId[u.id] = u;
        }
      }
      for (final u in followers) {
        if (u.id > 0) {
          byId[u.id] = u;
        }
      }
      setState(() {
        _socialSearchUsers = byId.values.toList();
      });
      _recomputeProfileMatchesIfNeeded();
    } catch (e, s) {
      AppLogger.warnSilencedError('SearchPage._loadSocialGraphForSearch', e, s);
    }
  }

  /// Sayfa açılırken arka planda tüm kullanıcı dizinini çeker.
  /// Başarılı olursa aramalar anında sonuç verir (network gecikmesi olmadan).
  Future<void> _preloadUserDirectory() async {
    try {
      final users = await _authService.fetchUserDirectory(maxPages: 1, pageSize: 100);
      if (!mounted || users.isEmpty) return;
      _preloadedUsers = users;
      _recomputeProfileMatchesIfNeeded();
    } catch (e, s) {
      AppLogger.warnSilencedError('SearchPage._preloadUserDirectory', e, s);
    }
  }

  void _scheduleTopReviewerRefresh() {
    _topReviewersRefreshTimer?.cancel();
    _topReviewersRefreshTimer = Timer.periodic(_topReviewersRefreshInterval, (_) {
      unawaited(
        _loadTopReviewers(
          force: true,
          silentLoading: true,
        ),
      );
    });
  }

  /// Token zorunlu; giriş yok veya hata → sessizce boş
  Future<void> _loadTopReviewers({
    bool force = false,
    bool silentLoading = false,
  }) async {
    if (!mounted) return;
    if (_loadingTopReviewers && !force) return;
    final cachedReviewers = SearchWarmCache.instance.peekTopReviewers();
    final cachedAt = SearchWarmCache.instance.peekTopReviewersFetchedAt();
    final cacheIsFresh = !force &&
        cachedReviewers.isNotEmpty &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _topReviewersRefreshInterval;

    if (cacheIsFresh) {
      if (mounted && _topReviewers != cachedReviewers) {
        setState(() {
          _topReviewers = cachedReviewers;
          _loadingTopReviewers = false;
        });
      }
      _recomputeProfileMatchesIfNeeded();
      return;
    }

    final shouldShowLoader = !silentLoading && _topReviewers.isEmpty;
    if (shouldShowLoader) {
      setState(() => _loadingTopReviewers = true);
    }
    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        if (mounted) {
          setState(() {
            _topReviewers = [];
            _loadingTopReviewers = false;
          });
        }
        return;
      }
      final list = await _reviewRepository.getTopReviewers(token, limit: 5);
      if (!mounted) return;
      SearchWarmCache.instance.rememberTopReviewers(list);
      setState(() {
        _topReviewers = list;
        _loadingTopReviewers = false;
      });
      _recomputeProfileMatchesIfNeeded();
    } catch (e, s) {
      AppLogger.warnSilencedError('SearchPage._loadTopReviewers', e, s);
      if (mounted) {
        setState(() {
          _topReviewers = [];
          _loadingTopReviewers = false;
        });
      }
    }
  }

  void _applyProductFromReviewExit(ReviewPagePopResult r) {
    final id = r.product.id;
    seedProductCardSocialCaches(
      id,
      likeCount: r.likeCount,
      reviewCount: r.reviewCount,
      rating: r.product.averageRating ?? 0.0,
    );
    if (!mounted) return;
    setState(() {
      _productCardResync[id] = (_productCardResync[id] ?? 0) + 1;
      final si = _searchResults.indexWhere((p) => p.id == id);
      if (si != -1) {
        _searchResults[si] = r.product;
      }
      final ai = _allProducts.indexWhere((p) => p.id == id);
      if (ai != -1) {
        _allProducts[ai] = r.product;
      }
    });
  }

  Future<void> _refreshProductAfterReview(String productId) async {
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (token == null) return;
      final updated = await _productRepository.getProductById(
        productId,
        firebaseIdToken: token,
        bypassCache: true,
      );
      final like = await _interactionRepository.getProductLikeCount(productId);
      final reviews = await _reviewRepository.getReviewsByProductId(
        productId,
        firebaseIdToken: token,
      );
      if (!mounted) return;
      final visible = filterVisibleReviews(reviews);
      final rc = visible.length;
      final sumRating = visible.fold<int>(0, (sum, r) => sum + r.rating);
      final computedRating = rc > 0 ? (sumRating / rc) : 0.0;
      setProductCardSocialCaches(
        productId,
        likeCount: like,
        reviewCount: rc,
        rating: computedRating,
      );
      if (!mounted) return;
      setState(() {
        _productCardResync[productId] = (_productCardResync[productId] ?? 0) + 1;
        final si = _searchResults.indexWhere((p) => p.id == productId);
        if (si != -1) {
          _searchResults[si] = updated;
        }
        final ai = _allProducts.indexWhere((p) => p.id == productId);
        if (ai != -1) {
          _allProducts[ai] = updated;
        }
      });
    } catch (e, s) {
      AppLogger.warnSilencedError('SearchPage._refreshProductAfterReview', e, s);
    }
  }

  void _onProductCardGridResync(String productId) {
    unawaited(_refreshProductAfterReview(productId));
  }

  Future<void> _primeSocialCountsForProducts(
    List<ProductDto> products, {
    int maxCount = 40,
  }) async {
    final targets = products
        .map((p) => p.id)
        .where((id) => id.isNotEmpty && !_socialCountsInFlight.contains(id))
        .take(maxCount)
        .toList();
    if (targets.isEmpty) return;
    for (final id in targets) {
      _socialCountsInFlight.add(id);
    }
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (token == null) return;
      final updates = await Future.wait(
        targets.map((id) async {
          final pair = await Future.wait([
            _interactionRepository.getProductLikeCount(id),
            _reviewRepository.getReviewsByProductId(id, firebaseIdToken: token),
          ]);
          final like = pair[0] as int;
          final visible = filterVisibleReviews(pair[1] as List<ReviewDto>);
          final reviewCount = visible.length;
          final sumRating = visible.fold<int>(0, (sum, r) => sum + r.rating);
          final rating = reviewCount > 0 ? (sumRating / reviewCount) : 0.0;
          return (id: id, like: like, reviewCount: reviewCount, rating: rating);
        }),
      );
      if (!mounted) return;
      setState(() {
        for (final u in updates) {
          setProductCardSocialCaches(
            u.id,
            likeCount: u.like,
            reviewCount: u.reviewCount,
            rating: u.rating,
          );
          _productCardResync[u.id] = (_productCardResync[u.id] ?? 0) + 1;
        }
      });
    } catch (e, s) {
      AppLogger.warnSilencedError('SearchPage._primeSocialCountsForProducts', e, s);
    } finally {
      for (final id in targets) {
        _socialCountsInFlight.remove(id);
      }
    }
  }

  void _replaceProductInLocalLists(String productId, ProductDto next) {
    final si = _searchResults.indexWhere((p) => p.id == productId);
    if (si != -1) {
      _searchResults[si] = next;
    }
    final ai = _allProducts.indexWhere((p) => p.id == productId);
    if (ai != -1) {
      _allProducts[ai] = next;
    }
  }

  Future<void> _toggleProductLikeFromSearch(ProductDto product) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      CustomSnackBar.showWithMessenger(
        messenger,
        message: 'Please login to like products',
        variant: CustomSnackBarVariant.error,
      );
      return;
    }
    final id = product.id;
    if (_productLikeInFlight.contains(id)) return;
    _productLikeInFlight.add(id);
    try {
      final currentIndex = _searchResults.indexWhere((p) => p.id == id);
      final current = currentIndex != -1 ? _searchResults[currentIndex] : product;
      final beforeLike = current.isLiked ?? false;
      applyLocalLikeCountDeltaOnToggle(
        id,
        wasLiked: beforeLike,
        isNowLiked: !beforeLike,
      );
      if (mounted) {
        setState(() {
          _replaceProductInLocalLists(id, current.copyWith(isLiked: !beforeLike));
        });
      }

      try {
        final token = await _sessionHelper.getTokenAndSetHeader();
        if (token == null) {
          throw Exception('Failed to get Firebase ID token');
        }
        final newLikeStatus = await _interactionRepository.toggleProductLike(
          token,
          id,
        );
        if (newLikeStatus != !beforeLike) {
          applyLocalLikeCountDeltaOnToggle(
            id,
            wasLiked: !beforeLike,
            isNowLiked: newLikeStatus,
          );
        }
        if (mounted) {
          setState(() {
            final latestIndex = _searchResults.indexWhere((p) => p.id == id);
            final latest = latestIndex != -1 ? _searchResults[latestIndex] : current;
            _replaceProductInLocalLists(id, latest.copyWith(isLiked: newLikeStatus));
          });
        }
      } catch (e) {
        applyLocalLikeCountDeltaOnToggle(
          id,
          wasLiked: !beforeLike,
          isNowLiked: beforeLike,
        );
        if (mounted) {
          setState(() {
            final latestIndex = _searchResults.indexWhere((p) => p.id == id);
            final latest = latestIndex != -1 ? _searchResults[latestIndex] : current;
            _replaceProductInLocalLists(id, latest.copyWith(isLiked: beforeLike));
          });
          CustomSnackBar.showWithMessenger(
            messenger,
            message: ErrorHandler.getUserFriendlyMessage(e),
            variant: CustomSnackBarVariant.error,
          );
        }
      }
      unawaited(_refreshProductAfterReview(id));
    } finally {
      _productLikeInFlight.remove(id);
    }
  }

  Future<void> _hookNotificationsIfSignedIn() async {
    final t = await _sessionHelper.ensureSession();
    if (!mounted || t == null) return;
    NotificationRealtimeService.instance.attach();
    _notificationSvcAttached = true;
    await NotificationRealtimeService.instance.refreshUnread();
  }

  @override
  void dispose() {
    unregisterProductCardGridResyncHandler(_onProductCardGridResync);
    if (_notificationSvcAttached) {
      NotificationRealtimeService.instance.detach();
    }
    _topReviewersRefreshTimer?.cancel();
    _searchDebounce?.cancel();
    _userSearchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final warmTags = SearchWarmCache.instance.peekRootTags();
    final warmProducts = SearchWarmCache.instance.peekSeedProducts();
    if (warmTags.isNotEmpty || warmProducts.isNotEmpty) {
      setState(() {
        _rootCategories = warmTags;
        _currentCategories = warmTags;
        _allProducts = warmProducts;
        _isLoading = false;
        _errorMessage = null;
      });
      unawaited(_refreshInitialDataInBackground());
      final warmTopReviewers = SearchWarmCache.instance.peekTopReviewers();
      if (warmTopReviewers.isNotEmpty) {
        setState(() {
          _topReviewers = warmTopReviewers;
          _loadingTopReviewers = false;
        });
      }
      unawaited(_loadTopReviewers(silentLoading: true));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      final warmTopReviewers = SearchWarmCache.instance.peekTopReviewers();
      if (warmTopReviewers.isNotEmpty) {
        _topReviewers = warmTopReviewers;
        _loadingTopReviewers = false;
      }
    });

    try {
      // Token opsiyonel: kategoriler için beklemeyelim, ilk ekran daha hızlı açılsın.
      final tokenFuture = _sessionHelper.ensureSession();
      List<TagDto> rootTags = [];
      try {
        rootTags = await _tagRepository.getRootTags();
      } catch (_) {}
      final token = await tokenFuture;
      _firebaseIdToken = token;

      if (!mounted) return;
      setState(() {
        _rootCategories = rootTags;
        _currentCategories = rootTags;
        _isLoading = false;
      });
      SearchWarmCache.instance.rememberRootTags(rootTags);

      // Tüm ürünleri yükle — yerel arama tüm veritabanında çalışsın
      try {
        final products = await _productRepository.getAllProductsRaw();
        if (!mounted) return;
        setState(() {
          _allProducts = products;
        });
        SearchWarmCache.instance.rememberSeedProducts(products);
      } catch (e, s) {
        AppLogger.warnSilencedError('SearchPage._loadInitialData.getAllProductsRaw', e, s);
        // Ürünler yüklenemezse arama boş kalır, kategoriler çalışır
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
          _isLoading = false;
        });
      }
    }
    final warmTopReviewers = SearchWarmCache.instance.peekTopReviewers();
    if (warmTopReviewers.isNotEmpty) {
      setState(() {
        _topReviewers = warmTopReviewers;
        _loadingTopReviewers = false;
      });
    }
    unawaited(_loadTopReviewers(silentLoading: true));
  }

  Future<void> _refreshInitialDataInBackground() async {
    try {
      final token = await _sessionHelper.ensureSession();
      _firebaseIdToken = token;

      List<TagDto> rootTags = [];
      try {
        rootTags = await _tagRepository.getRootTags(token);
      } catch (e, s) {
        AppLogger.warnSilencedError('SearchPage._refreshInitialDataInBackground.getRootTags', e, s);
      }
      if (rootTags.isNotEmpty) {
        SearchWarmCache.instance.rememberRootTags(rootTags);
        if (mounted) {
          final keepCurrentCategoryContext =
              _searchController.text.trim().isEmpty &&
              (_categoryPath.isNotEmpty || _showCategoryResults);
          setState(() {
            _rootCategories = rootTags;
            if (!keepCurrentCategoryContext) {
              _currentCategories = rootTags;
            }
          });
        }
      }

      try {
        final products = await _productRepository.getAllProductsRaw();
        SearchWarmCache.instance.rememberSeedProducts(products);
        if (mounted) {
          setState(() {
            _allProducts = products;
          });
        }
      } catch (e, s) {
        AppLogger.warnSilencedError('SearchPage._refreshInitialDataInBackground.getAllProductsRaw', e, s);
      }
    } catch (e, s) {
      AppLogger.warnSilencedError('SearchPage._refreshInitialDataInBackground', e, s);
    }
  }

  Future<void> _refreshSearchPage() async {
    await Future.wait<void>([
      _refreshInitialDataInBackground(),
      _loadTopReviewers(force: true, silentLoading: true),
      _loadSocialGraphForSearch(),
    ]);
    if (_searchController.text.trim().isEmpty &&
        _showCategoryResults &&
        _activeLeafCategory != null) {
      try {
        final products = await _productRepository.getProductsByTagId(
          _activeLeafCategory!.id,
          firebaseIdToken: _firebaseIdToken,
        );
        if (mounted) {
          setState(() {
            _searchResults = products;
          });
        }
        unawaited(_primeSocialCountsForProducts(products));
      } catch (_) {}
    }
    final q = _searchController.text.trim();
    if (q.isNotEmpty && mounted) {
      await _onSearchChanged(q);
    }
    if (!mounted) return;
    if (_searchResults.isNotEmpty) {
      for (final p in _searchResults) {
        final id = p.id.trim();
        if (id.isEmpty) continue;
        invalidateProductCardSocialCaches(id);
        _productCardResync[id] = (_productCardResync[id] ?? 0) + 1;
      }
      setState(() {});
    }
  }

  Future<void> _openCategory(TagDto category) async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      final token = _firebaseIdToken ?? await _sessionHelper.ensureSession();
      _firebaseIdToken = token;
      TagChildrenResponse response;
      try {
        response = await _tagRepository.getTagChildren(category.id, token);
      } catch (_) {
        response = await _tagRepository.getTagChildren(category.id, null);
      }
      if (response.children.isNotEmpty) {
        setState(() {
          _categoryHistory.add(_currentCategories);
          _categoryPath.add(category);
          _currentCategories = response.children;
          _showCategoryResults = false;
          _activeLeafCategory = null;
          _searchResults = [];
          _isLoadingCategories = false;
        });
        return;
      }

      final products = await _productRepository.getProductsByTagId(
        category.id,
        firebaseIdToken: _firebaseIdToken,
      );

      setState(() {
        _activeLeafCategory = category;
        _showCategoryResults = true;
        _searchResults = products;
        _isLoadingCategories = false;
      });
      unawaited(_primeSocialCountsForProducts(products));
      ReviewPrefetchService.instance.prefetchForProducts(
        products,
        maxCount: 6,
      );
    } catch (e) {
      setState(() {
        _isLoadingCategories = false;
      });
      if (!mounted) return;
      CustomSnackBar.show(
        context,
        message: ErrorHandler.getUserFriendlyMessage(e),
        variant: CustomSnackBarVariant.error,
      );
    }
  }

  void _goBackCategoryLevel() {
    if (_showCategoryResults) {
      setState(() {
        _showCategoryResults = false;
        _activeLeafCategory = null;
        _searchResults = [];
      });
      return;
    }

    if (_categoryHistory.isEmpty) return;
    setState(() {
      _currentCategories = _categoryHistory.removeLast();
      if (_categoryPath.isNotEmpty) {
        _categoryPath.removeLast();
      }
      _searchResults = [];
    });
  }

  Widget _buildSearchResultsBody() {
    final hasProfiles = _profileSearchMatches.isNotEmpty;
    final hasProducts = _searchResults.isNotEmpty;
    if (!hasProfiles && !hasProducts) {
      return const Center(
        child: Text(
          'No matching products or people',
          style: AppTextStyles.bodySecondary,
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasProfiles) ...[
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              'Profiles',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _profileSearchMatches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final e = _profileSearchMatches[index];
                return _ProfileSearchHitRow(
                  entry: e,
                  onTap: () {
                    if (e.userId.isEmpty) return;
                    openUserProfileIfActive(
                      context,
                      userId: e.userId,
                      userName: e.userName,
                      profileImageUrl: e.profileImageUrl,
                    );
                  },
                );
              },
            ),
          ),
          if (hasProducts) const SizedBox(height: AppSpacing.large),
        ],
        if (hasProducts && hasProfiles)
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              'Products',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
        Expanded(
          child: hasProducts
              ? GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.xLarge,
                    mainAxisSpacing: AppSpacing.xLarge,
                    childAspectRatio: 0.60,
                  ),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final product = _searchResults[index];
                    return ProductCard(
                      key: ValueKey('spq_${product.id}_${_productCardResync[product.id] ?? 0}'),
                      productId: product.id,
                      imageUrl: product.imageURL,
                      title: product.name,
                      category: product.tag.name,
                      categoryPath: product.tag.categoryPath,
                      rating: product.averageRating ?? 0.0,
                      desc: product.description ?? '',
                      isFavorite: product.isLiked ?? false,
                      loadReviewCount: true,
                      fetchSocialCounts: true,
                      onTap: () async {
                        final r = await Navigator.push<ReviewPagePopResult?>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReviewPage(product: product),
                          ),
                        );
                        if (!mounted) return;
                        if (r != null) {
                          _applyProductFromReviewExit(r);
                        } else {
                          unawaited(_refreshProductAfterReview(product.id));
                        }
                      },
                      onFavoriteTap: () => unawaited(
                        _toggleProductLikeFromSearch(product),
                      ),
                    );
                  },
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xLarge),
                    child: Text(
                      hasProfiles
                          ? 'No products match this search'
                          : 'No matching products or people',
                      style: AppTextStyles.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Refresh veya programatik tetiklemeler için (ör. _refreshSearchPage).
  /// Kullanıcı yazarken çağrılmaz; bunun yerine [_handleSearchInputChanged] kullanılır.
  Future<void> _onSearchChanged(String query) async {
    final q = query.trim().toLowerCase();
    _activeQuery = q;
    if (q.isEmpty) {
      _serverUserResults = [];
      _serverUserResultsQuery = '';
      setState(() {
        _searchResults = [];
        _profileSearchMatches = [];
        _isSearching = false;
        _showCategoryResults = false;
        _activeLeafCategory = null;
        _currentCategories = _rootCategories;
        _categoryHistory.clear();
        _categoryPath.clear();
      });
      return;
    }

    setState(() {
      _showCategoryResults = false;
      _activeLeafCategory = null;
    });

    final results = _filterProducts(q);
    if (!mounted || _activeQuery != q) return;
    setState(() {
      _searchResults = results;
      _profileSearchMatches = _resolveProfileMatches(q);
    });
    unawaited(_primeSocialCountsForProducts(results));
    ReviewPrefetchService.instance.prefetchForProducts(results, maxCount: 6);
    unawaited(_searchUsersFromServer(q));
  }

  /// Ürün filtrelemesi — lokal liste üzerinde senkron çalışır.
  List<ProductDto> _filterProducts(String q) {
    if (q.isEmpty) return const [];
    return _allProducts.where((product) {
      final productName = product.name.toLowerCase();
      final tagName = product.tag.name.toLowerCase();
      final tagPathSegments = (product.tag.categoryPath ?? '')
          .toLowerCase()
          .split('.')
          .where((s) => s.isNotEmpty)
          .toList();
      return productName.contains(q) ||
          tagName.contains(q) ||
          tagPathSegments.any((s) => s.contains(q));
    }).toList();
  }

  /// Aktif query için anlık profil eşleşmelerini hesaplar.
  /// Öncelik sırası: server cache → preloaded directory → lokal (top reviewers + social graph).
  List<_ProfileSearchEntry> _resolveProfileMatches(String q) {
    // 1. Server cache tam eşleşme
    if (_serverUserResultsQuery == q && _serverUserResults.isNotEmpty) {
      return _mergeProfileMatches(q, _serverUserResults);
    }

    // 2. Server cache daraltma (ör. "ali" cache'i varken "alic" yazıldı)
    if (_serverUserResultsQuery.isNotEmpty &&
        q.startsWith(_serverUserResultsQuery) &&
        _serverUserResults.isNotEmpty) {
      final narrowed = _serverUserResults
          .where((u) => (u.userName as String).toLowerCase().contains(q))
          .toList();
      if (narrowed.isNotEmpty) return _mergeProfileMatches(q, narrowed);
    }

    // 3. Preloaded directory — sayfanın açılışında yüklendi, network yok
    if (_preloadedUsers.isNotEmpty) {
      final fromDir = _preloadedUsers
          .where((u) => (u.userName as String).toLowerCase().contains(q))
          .toList();
      if (fromDir.isNotEmpty) return _mergeProfileMatches(q, fromDir);
    }

    // 4. Fallback: sadece lokal (top reviewers + social graph)
    return _computeProfileMatches(q);
  }

  void _handleSearchInputChanged(String query) {
    _userSearchDebounce?.cancel();
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      _activeQuery = '';
      _serverUserResults = [];
      _serverUserResultsQuery = '';
      setState(() {
        _searchResults = [];
        _profileSearchMatches = [];
        _isSearching = false;
        _showCategoryResults = false;
        _activeLeafCategory = null;
        _currentCategories = _rootCategories;
        _categoryHistory.clear();
        _categoryPath.clear();
      });
      return;
    }

    // Cache'i sıfırla: yeni query önceki cache'le ilgisizse.
    if (_serverUserResultsQuery.isNotEmpty &&
        !q.startsWith(_serverUserResultsQuery) &&
        !_serverUserResultsQuery.startsWith(q)) {
      _serverUserResults = [];
      _serverUserResultsQuery = '';
    }

    _activeQuery = q;

    // Lokal sonuçları debounce olmadan anında göster.
    final productResults = _filterProducts(q);
    setState(() {
      _showCategoryResults = false;
      _activeLeafCategory = null;
      _searchResults = productResults;
      _profileSearchMatches = _resolveProfileMatches(q);
    });
    unawaited(_primeSocialCountsForProducts(productResults));
    ReviewPrefetchService.instance.prefetchForProducts(productResults, maxCount: 6);

    // Server user search: kullanıcı yazmayı bırakınca tetikle.
    _userSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_searchUsersFromServer(q));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Search',
          style: AppTextStyles.heading2.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const SearchPageBodySkeleton()
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xLarge),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body,
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refreshSearchPage,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: ClampingScrollPhysics(),
                      ),
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xLarge),
                          child: Column(
                            children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        decoration: _premiumSurface(
                          radius: 18,
                          borderColor: _searchFocusNode.hasFocus
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _handleSearchInputChanged,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search user, products or categories',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary.withValues(alpha: 0.7),
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: _searchFocusNode.hasFocus
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              size: 22,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      _searchController.clear();
                                      _handleSearchInputChanged('');
                                      _searchFocusNode.unfocus();
                                    },
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: AppColors.textSecondary,
                                      size: 20,
                                    ),
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 15,
                            ),
                          ),
                        ),
                      ),
                      if (_searchController.text.trim().isEmpty) ...[
                        if (_loadingTopReviewers && _topReviewers.isEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                            decoration: _premiumSurface(radius: 18),
                            child: Column(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    'Top 5 Reviewers',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                      letterSpacing: 0.2,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                SizedBox(
                                  height: 114,
                                  child: Row(
                                    children: List.generate(
                                      5,
                                      (index) => Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            left: index == 0 ? 0 : 4,
                                            right: index == 4 ? 0 : 4,
                                          ),
                                          child: _TopReviewerRow(
                                            rank: index + 1,
                                            data: null,
                                            isCurrentUser: false,
                                            onTap: null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (_topReviewers.isNotEmpty) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                            decoration: _premiumSurface(radius: 18),
                            child: Column(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    'Top 5 Reviewers',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                      letterSpacing: 0.2,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                // Alt rozetlere alan açmak için ekstra boşluk
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: SizedBox(
                                  height: 114,
                                  child: Row(
                                    children: List.generate(5, (index) {
                                      final hasData = index < _topReviewers.length;
                                      final t = hasData ? _topReviewers[index] : null;
                                      return Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            left: index == 0 ? 0 : 4,
                                            right: index == 4 ? 0 : 4,
                                          ),
                                          child: _TopReviewerRow(
                                            rank: index + 1,
                                            data: t,
                                            isCurrentUser:
                                                hasData &&
                                                _currentUserId != null &&
                                                t!.userId.trim() ==
                                                    _currentUserId!.trim(),
                                            onTap: hasData
                                                ? () {
                                                    if (t!.userId.isEmpty) return;
                                                    final meId = _currentUserId?.trim();
                                                    final tappedId = t.userId.trim();
                                                    if (meId != null &&
                                                        meId.isNotEmpty &&
                                                        tappedId == meId) {
                                                      Navigator.pushReplacement(
                                                        context,
                                                        _noAnimationRoute(
                                                          const ProfilePage(),
                                                        ),
                                                      );
                                                      return;
                                                    }
                                                    openUserProfileIfActive(
                                                      context,
                                                      userId: t.userId,
                                                      userName: t.userName,
                                                      profileImageUrl: t.profileImageUrl,
                                                    );
                                                  }
                                                : null,
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                                ), // Padding(bottom:14)
                              ],
                            ),
                          ),
                        ],
                      ],
                      if ((_searchController.text.trim().isEmpty) &&
                          (_loadingTopReviewers || _topReviewers.isNotEmpty))
                        const SizedBox(height: AppSpacing.small),
                      const SizedBox(height: AppSpacing.xLarge),
                      Expanded(
                        child: _searchController.text.trim().isNotEmpty
                            ? (_isSearching
                            ? const Center(child: ListLoadMoreSkeleton())
                            : _buildSearchResultsBody())
                            : _showCategoryResults
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              IconButton(
                                                onPressed: _goBackCategoryLevel,
                                                icon: const Icon(
                                                  Icons.arrow_back_ios_new,
                                                  size: 16,
                                                  color: AppColors.primary,
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(
                                                  minWidth: 22,
                                                  minHeight: 22,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _buildCategoryBreadcrumb(
                                                    _categoryPath,
                                                    leaf: _activeLeafCategory,
                                                  ),
                                                  style: AppTextStyles.bodySecondary,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Expanded(
                                            child: _searchResults.isEmpty
                                                ? const Center(
                                                    child: Text(
                                                      'No products found in this category',
                                                      style: AppTextStyles.bodySecondary,
                                                    ),
                                                  )
                                                : GridView.builder(
                                                    gridDelegate:
                                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                                      crossAxisCount: 2,
                                                      crossAxisSpacing: AppSpacing.xLarge,
                                                      mainAxisSpacing: AppSpacing.xLarge,
                                                      childAspectRatio: 0.60,
                                                    ),
                                                    itemCount: _searchResults.length,
                                                    itemBuilder: (context, index) {
                                                      final product = _searchResults[index];
                                                      return ProductCard(
                                                        key: ValueKey('spc_${product.id}_${_productCardResync[product.id] ?? 0}'),
                                                        productId: product.id,
                                                        imageUrl: product.imageURL,
                                                        title: product.name,
                                                        category: product.tag.name,
                                                        categoryPath: product.tag.categoryPath,
                                                        rating: product.averageRating ?? 0.0,
                                                        desc: product.description ?? '',
                                                        isFavorite: product.isLiked ?? false,
                                                        loadReviewCount: true,
                                                        fetchSocialCounts: true,
                                                        onTap: () async {
                                                          final r = await Navigator.push<ReviewPagePopResult?>(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) => ReviewPage(product: product),
                                                            ),
                                                          );
                                                          if (!mounted) return;
                                                          if (r != null) {
                                                            _applyProductFromReviewExit(r);
                                                          } else {
                                                            unawaited(_refreshProductAfterReview(product.id));
                                                          }
                                                        },
                                                        onFavoriteTap: () => unawaited(
                                                          _toggleProductLikeFromSearch(product),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                          ),
                                        ],
                                      )
                                : _isLoadingCategories
                                    ? ListView.separated(
                                        padding: EdgeInsets.zero,
                                        itemCount: 8,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: AppSpacing.small),
                                        itemBuilder: (_, __) => SkeletonLoader(
                                          width: double.infinity,
                                          height: 52,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              decoration: _premiumSurface(radius: 18),
                                              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (_categoryPath.isEmpty)
                                                    const Padding(
                                                      padding: EdgeInsets.only(bottom: 10),
                                                      child: Center(
                                                        child: Text(
                                                          'Categories',
                                                          style: TextStyle(
                                                            fontSize: 22,
                                                            fontWeight: FontWeight.w800,
                                                            color: AppColors.textPrimary,
                                                            letterSpacing: 0.2,
                                                          ),
                                                        ),
                                                      ),
                                                    )
                                                  else ...[
                                                    Row(
                                                      children: [
                                                        IconButton(
                                                          onPressed: _goBackCategoryLevel,
                                                          icon: const Icon(
                                                            Icons.arrow_back_ios_new,
                                                            size: 14,
                                                            color: AppColors.primary,
                                                          ),
                                                          padding: EdgeInsets.zero,
                                                          constraints: const BoxConstraints(
                                                            minWidth: 18,
                                                            minHeight: 18,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Expanded(
                                                          child: Text(
                                                            _categoryPath
                                                                .map((e) => _formatCategoryLabel(e.name))
                                                                .join(' > '),
                                                            style: AppTextStyles.bodySecondary.copyWith(
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                  ],
                                                  Expanded(
                                                    child: ListView.separated(
                                                      padding: EdgeInsets.zero,
                                                      itemCount: _currentCategories.length,
                                                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                                                      itemBuilder: (context, index) {
                                                        final category = _currentCategories[index];
                                                        return Material(
                                                          color: Colors.transparent,
                                                          borderRadius: BorderRadius.circular(14),
                                                          child: InkWell(
                                                            onTap: () => _openCategory(category),
                                                            borderRadius: BorderRadius.circular(14),
                                                            child: Container(
                                                              decoration: _premiumSurface(radius: 14),
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 14,
                                                                vertical: 13,
                                                              ),
                                                              child: Row(
                                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                                children: [
                                                                  Container(
                                                                    width: 17,
                                                                    height: 17,
                                                                    decoration: BoxDecoration(
                                                                      shape: BoxShape.circle,
                                                                      color: AppColors.primary.withValues(alpha: 0.08),
                                                                      border: Border.all(
                                                                        color: AppColors.primary.withValues(alpha: 0.35),
                                                                        width: 1,
                                                                      ),
                                                                    ),
                                                                    child: Center(
                                                                      child: Container(
                                                                        width: 5,
                                                                        height: 5,
                                                                        decoration: const BoxDecoration(
                                                                          color: AppColors.primary,
                                                                          shape: BoxShape.circle,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(width: 12),
                                                                  Expanded(
                                                                    child: Align(
                                                                      alignment: Alignment.centerLeft,
                                                                      child: Text(
                                                                        _formatCategoryLabel(category.name),
                                                                        style: const TextStyle(
                                                                          fontSize: 15,
                                                                          fontWeight: FontWeight.w500,
                                                                          color: AppColors.textPrimary,
                                                                          height: 1.1,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const Icon(
                                                                    Icons.chevron_right_rounded,
                                                                    size: 18,
                                                                    color: AppColors.textSecondary,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                      ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        showSelectedLabels: false,
        showUnselectedLabels: false,
      selectedFontSize: 0,
      unselectedFontSize: 0,
        onTap: (index) {
          if (index == 0) return;
          if (index == 1) {
            Navigator.pushReplacement(
              context,
              _noAnimationRoute(const FriendFeedPage()),
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
          if (index == 4) {
            Navigator.pushReplacement(
              context,
              _noAnimationRoute(const ProfilePage()),
            );
            return;
          }
        },
        items: MainBottomNavItems.barItems,
      ),
    );
  }
}

/// Arama: ürün dışı kullanıcı satırı
class _ProfileSearchEntry {
  const _ProfileSearchEntry({
    required this.userId,
    required this.userName,
    this.profileImageUrl,
  });

  final String userId;
  final String userName;
  final String? profileImageUrl;
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

String _buildCategoryBreadcrumb(
  List<TagDto> path, {
  TagDto? leaf,
}) {
  final items = <String>[
    ...path.map((e) => _formatCategoryLabel(e.name)),
    if (leaf != null) _formatCategoryLabel(leaf.name),
  ];
  return items.join(' > ');
}

BoxDecoration _premiumSurface({
  Color color = AppColors.surface,
  double radius = 16,
  Color borderColor = AppColors.border,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor.withValues(alpha: 0.65), width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 14,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.02),
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

class _ProfileSearchHitRow extends StatelessWidget {
  const _ProfileSearchHitRow({
    required this.entry,
    required this.onTap,
  });

  final _ProfileSearchEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 172,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.75),
              width: 1,
            ),
            color: AppColors.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              ProfileAvatarImage(
                size: 34,
                imageUrl: entry.profileImageUrl,
                fallbackInitial: entry.userName,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.userName.isNotEmpty ? '@${entry.userName}' : '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopReviewerRow extends StatelessWidget {
  const _TopReviewerRow({
    required this.rank,
    required this.data,
    required this.isCurrentUser,
    required this.onTap,
  });

  final int rank;
  final TopReviewerDto? data;
  final bool isCurrentUser;
  final VoidCallback? onTap;

  // Sıra rozeti renkleri — altın / gümüş / bronz / pastel
  static const _badgeColors = [
    Color(0xFFFFB800), // 1 — altın
    Color(0xFFADB8C8), // 2 — gümüş
    Color(0xFFBB7B3A), // 3 — bronz
    Color(0xFF8FA0BE), // 4
    Color(0xFF8FA0BE), // 5
  ];

  static const _badgeTextColors = [
    Color(0xFF7A4F00),
    Color(0xFF3A4050),
    Color(0xFF5C3318),
    Color(0xFF2E3F6B),
    Color(0xFF2E3F6B),
  ];

  @override
  Widget build(BuildContext context) {
    final username = (data?.userName ?? '').trim();
    final reviewLabel = data == null
        ? ' '
        : '${data!.reviewCount} ${data!.reviewCount == 1 ? 'review' : 'reviews'}';
    final badgeColor = _badgeColors[(rank - 1).clamp(0, 4)];
    final badgeTextColor = _badgeTextColors[(rank - 1).clamp(0, 4)];
    final isTopThree = rank <= 3;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        // Stack + clipBehavior: none → rozet kartın altından çıkıyor
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Ana kart
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCurrentUser
                      ? AppColors.primary.withValues(alpha: 0.85)
                      : isTopThree
                          ? badgeColor.withValues(alpha: 0.45)
                          : AppColors.border.withValues(alpha: 0.7),
                  width: isCurrentUser ? 1.5 : (isTopThree ? 1.2 : 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isTopThree
                        ? badgeColor.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar — ilk 3'te renkli halka
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isTopThree
                          ? LinearGradient(
                              colors: [
                                badgeColor.withValues(alpha: 0.9),
                                badgeColor.withValues(alpha: 0.4),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isTopThree ? null : Colors.transparent,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(
                        width: 42,
                        height: 42,
                        child: ProfileAvatarImage(
                          size: 42,
                          imageUrl: data?.profileImageUrl,
                          fallbackInitial: username.isNotEmpty ? username : '?',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 13,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          username.isNotEmpty ? '@$username' : '—',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10.2,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 12,
                    child: Center(
                      child: Text(
                        reviewLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 9.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Sıra rozeti — kartın altından çıkıyor
            Positioned(
              bottom: -12,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeColor,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: badgeColor.withValues(alpha: 0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: rank == 1 ? 12 : 11,
                      fontWeight: FontWeight.w900,
                      color: badgeTextColor,
                      height: 1,
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


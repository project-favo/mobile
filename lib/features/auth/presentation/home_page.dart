import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/session_helper.dart';
import '../../../core/utils/entity_active.dart';
import '../../../core/notifications/notification_realtime_service.dart';
import '../../../core/notifications/message_unread_service.dart';
import '../../../core/widgets/main_bottom_nav_items.dart';
import '../../../features/activity/presentation/activity_page.dart';
import '../../../core/widgets/custom_refresh_indicator.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/product_request_notice.dart';
import '../../../core/routes/custom_page_transitions.dart';
import '../../../core/utils/in_flight_id_lock.dart';
import '../../../core/cache/following_id_set_cache.dart';
import '../../../core/cache/home_feed_cache.dart';
import '../../../core/cache/home_top_picks_cache.dart';
import '../../../core/cache/home_view_state_cache.dart';
import '../../../core/config/app_background_timers.dart';
import '../../../core/cache/search_warm_cache.dart';
import '../../../core/cache/friend_feed_memory_cache.dart';
import '../../../core/cache/home_friend_liker_prefs.dart';
import '../../../core/cache/current_user_cache.dart';
import '../../../features/activity/domain/activity_models.dart';
import '../../../features/activity/domain/activity_type.dart';
import '../../../features/activity/data/friends_feed_repository.dart';
import '../../../features/activity/data/friends_feed_dto.dart';
import '../../../features/activity/data/friends_feed_activity_mapper.dart';
import '../widgets/product_card.dart';
import '../../../core/widgets/custom_snack_bar.dart';
import 'messages/conversation_list_page.dart';
import 'messages/ai_chat_page.dart';
import 'search_page.dart';
import 'friend_feed_page.dart';
import 'profile/pages/profile_page.dart';
import 'review/pages/review_page.dart';
import 'review/review_page_pop_result.dart';
import '../data/repositories/tag_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/review_repository.dart';
import '../data/repositories/interaction_repository.dart';
import '../data/services/auth_service.dart';
import '../data/services/review_prefetch_service.dart';
import '../data/models/tag_dto.dart';
import '../data/models/product_dto.dart';
import '../data/models/product_search_result_dto.dart';
import '../data/models/review_dto.dart';
import '../data/models/feed_sort_option.dart';

/// Aynı [FriendsFeedItemDto.id] tekrarlandığında farklı yorumcuların satırını atmamak için.
String _friendsFeedDtoDedupeKey(FriendsFeedItemDto e) {
  final id = e.id.trim();
  final aid = e.actorUserId.trim();
  final pid = (e.productId ?? '').trim();
  final rid = (e.reviewId ?? '').trim();
  final t = e.type.trim();
  if (id.isNotEmpty) {
    return '$id|u:$aid|r:$rid|p:$pid';
  }
  return '$t|u:$aid|p:$pid|r:$rid|${e.createdAt?.millisecondsSinceEpoch ?? 0}';
}

/// [ActivityItem.id] çakışınca aynı üründe ikinci arkadaş baloncuğu kaybolmasın.
String _friendLikerActivityMergeKey(ActivityItem item) {
  final base = item.id.trim();
  final uid = item.user.id.trim();
  final rid = (item.targetContent?.reviewId ?? '').trim();
  final pid = (item.targetContent?.productId ?? '').trim();
  if (base.isNotEmpty) {
    return '$base|u:$uid|r:$rid|p:$pid';
  }
  return '${item.type.name}|u:$uid|p:$pid|r:$rid|${item.timestamp.millisecondsSinceEpoch}';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  static const int _kMaxFriendReviewBubblesPerProduct = 5;
  static const int _kMaxFriendLikerKeysPerProduct = 5;
  static const double _kScrollToTopThreshold = 520;

  // BottomNavigationBar index mapping:
  // 0: search, 1: add (placeholder), 2: home, 3: activity, 4: profile
  int _selectedCategoryIndex = -1; // -1 means "All", 0+ means selected category
  int _selectedSubCategoryIndex = -1; // -1 means none
  final TagRepository _tagRepository = TagRepository();
  final ProductRepository _productRepository = ProductRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  final InteractionRepository _interactionRepository = InteractionRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final AuthService _authService = AuthService();
  final FriendsFeedRepository _friendsFeedRepository = FriendsFeedRepository();

  List<TagDto> _tags = [];
  List<TagDto> _subTags = [];
  final Map<HomeTopPicksTab, List<ProductDto>> _topPicksByTab = {
    HomeTopPicksTab.weeklyLikes: [],
    HomeTopPicksTab.forYou: [],
  };
  final Set<HomeTopPicksTab> _topPicksLoadingTabs = <HomeTopPicksTab>{};
  final Map<HomeTopPicksTab, int> _topPicksLatestRequestByTab = {};
  int _topPicksRequestSeq = 0;
  // Active banner: null = home feed, otherwise shows banner products
  HomeTopPicksTab? _activeBannerTab;
  List<ProductDto> _filteredProducts = []; // Current page products
  int _currentPage = 0;
  int _totalPages = 0;
  int _totalElements = 0;
  String? _activeCategoryPathPrefix;
  FeedSortOption _activeSortOption = FeedSortOption.newest;
  bool _isLoading = true;
  bool _isFiltering = false;
  bool _isLoadingMore = false; // Infinite scroll: sonraki sayfa yüklenirken
  bool _isLoadingSubTags = false;
  String? _errorMessage;
  late final ScrollController _scrollController;
  bool _notificationSvcAttached = false;

  // --- Friend likers: (1) arkadaş feed aktiviteleri (2) ana vitrindeki ürünlerin yorumlarında
  // takip edilen yazarlar — feed sayfasına sığmayan yorumlar da baloncukta görünsün.
  List<ActivityItem> _friendFeedItemsForLikers = const [];
  Map<String, List<String>> _friendLikersMap = {};

  static const int _kFriendReviewSupplementMaxProducts = 36;
  static const int _kFriendReviewSupplementConcurrency = 5;
  static const Duration _kFriendReviewSupplementMinGap = Duration(seconds: 50);
  DateTime? _friendReviewSupplementCooldownUntil;
  int _friendReviewSupplementRequestId = 0;

  /// [ProductCard] key parçası — ürün detayından dönünce like sayısı tazelensin.
  final Map<String, int> _productCardResync = {};
  final InFlightIdLock _homeProductLikeLock = InFlightIdLock();
  /// Grid like ile çakışan [getProductById] / yenilemelerin eski [isLiked] ile üstüne yazmasını engeller.
  final Map<String, int> _homeLikeMutationEpoch = {};
  static const Duration _homeLikeOverrideTtl = Duration(minutes: 3);
  final Map<String, ({bool liked, DateTime at})> _homeLikeOverrides = {};

  // --- Banner collapse state ---
  bool _isBannerCollapsed = false;

  // --- Inline search (aynı katalog: Search ekranı gibi tüm ürünler) ---
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<ProductDto> _searchResults = [];
  Timer? _searchDebounce;
  // Home araması her zaman tam katalogda çalışsın (SearchPage ile aynı davranış).
  List<ProductDto> _fullSearchCatalog = [];
  Future<List<ProductDto>>? _fullSearchCatalogFuture;
  /// Tüm kategori ana sayfasında: yeni ürünler için arka planda periyodik kontrol.
  Timer? _homeFeedPollTimer;
  bool _homeFeedPollInFlight = false;
  /// Her N ana sayfa poll’unda arkadaş feed’i yenile (like → avatar haritası güncellensin).
  int _friendFeedRefreshPollTick = 0;
  int _searchReqSeq = 0;
  bool _isSearchLoading = false;
  bool _showScrollToTop = false;
  double? _pendingRestoreOffset;
  int _restoreScrollAttemptsLeft = 0;
  String _homeViewStateUserId = '';

  void _putHomeLikeOverride(String productId, bool liked) {
    if (productId.isEmpty) return;
    _homeLikeOverrides[productId] = (liked: liked, at: DateTime.now());
  }

  void _pruneHomeLikeOverrides() {
    final now = DateTime.now();
    _homeLikeOverrides.removeWhere(
      (_, v) => now.difference(v.at) > _homeLikeOverrideTtl,
    );
  }

  bool _effectiveHomeLiked(ProductDto p) {
    _pruneHomeLikeOverrides();
    final ov = _homeLikeOverrides[p.id];
    if (ov != null) return ov.liked;
    return p.isLiked ?? false;
  }

  List<ProductDto> _applyHomeLikeOverrides(List<ProductDto> source) {
    if (source.isEmpty) return source;
    _pruneHomeLikeOverrides();
    var changed = false;
    final next = source.map((p) {
      final ov = _homeLikeOverrides[p.id];
      if (ov == null) return p;
      final cur = p.isLiked ?? false;
      if (cur == ov.liked) return p;
      changed = true;
      return p.copyWith(isLiked: ov.liked);
    }).toList();
    return changed ? next : source;
  }

  void _applyHomeLikeStatusLocally(String productId, bool liked) {
    _putHomeLikeOverride(productId, liked);
    final fi = _filteredProducts.indexWhere((p) => p.id == productId);
    if (fi != -1) {
      _filteredProducts[fi] = _filteredProducts[fi].copyWith(isLiked: liked);
    }
    for (final tab in HomeTopPicksTab.values) {
      final list = _topPicksByTab[tab]!;
      final i = list.indexWhere((p) => p.id == productId);
      if (i != -1) {
        final next = List<ProductDto>.from(list);
        next[i] = next[i].copyWith(isLiked: liked);
        _topPicksByTab[tab] = next;
      }
    }
    final si = _searchResults.indexWhere((p) => p.id == productId);
    if (si != -1) {
      _searchResults[si] = _searchResults[si].copyWith(isLiked: liked);
    }
  }

  Future<void> _toggleHomeProductLike(ProductDto product) async {
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
    final pid = product.id;
    if (!_homeProductLikeLock.tryEnter(pid)) {
      return;
    }
    _homeLikeMutationEpoch[pid] = (_homeLikeMutationEpoch[pid] ?? 0) + 1;
    final beforeLike = _effectiveHomeLiked(product);
    final optimistic = !beforeLike;
    applyLocalLikeCountDeltaOnToggle(
      pid,
      wasLiked: beforeLike,
      isNowLiked: optimistic,
    );
    if (mounted) {
      setState(() {
        _applyHomeLikeStatusLocally(pid, optimistic);
      });
    }
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (token == null) {
        throw Exception('Failed to get Firebase ID token');
      }
      final newLikeStatus = await _interactionRepository.toggleProductLike(token, pid);
      if (newLikeStatus != optimistic) {
        applyLocalLikeCountDeltaOnToggle(
          pid,
          wasLiked: optimistic,
          isNowLiked: newLikeStatus,
        );
      }
      if (mounted) {
        setState(() {
          _applyHomeLikeStatusLocally(pid, newLikeStatus);
        });
      }
    } catch (e) {
      applyLocalLikeCountDeltaOnToggle(
        pid,
        wasLiked: optimistic,
        isNowLiked: beforeLike,
      );
      if (mounted) {
        setState(() {
          _applyHomeLikeStatusLocally(pid, beforeLike);
        });
        CustomSnackBar.showWithMessenger(
          messenger,
          message: ErrorHandler.getUserFriendlyMessage(e),
          variant: CustomSnackBarVariant.error,
        );
      }
    } finally {
      _homeProductLikeLock.leave(pid);
    }
  }

  Route _noAnimationRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  void _rememberHomeViewState() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    if (_filteredProducts.isEmpty) return;
    HomeViewStateCache.instance.set(
      _homeViewStateUserId,
      HomeViewState(
        products: _filteredProducts,
        currentPage: _currentPage,
        totalPages: _totalPages,
        totalElements: _totalElements,
        selectedCategoryIndex: _selectedCategoryIndex,
        selectedSubCategoryIndex: _selectedSubCategoryIndex,
        activeCategoryPathPrefix: _activeCategoryPathPrefix,
        activeSortOption: _activeSortOption,
        scrollOffset: offset,
        isBannerCollapsed: _isBannerCollapsed,
      ),
    );
  }

  void _navigateFromHome(Widget page) {
    _rememberHomeViewState();
    Navigator.pushReplacement(context, _noAnimationRoute(page));
  }

  void _scheduleRestoreScrollOffset() {
    if (_pendingRestoreOffset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingRestoreOffset == null) return;
      if (!_scrollController.hasClients) {
        if (_restoreScrollAttemptsLeft > 0) {
          _restoreScrollAttemptsLeft--;
          _scheduleRestoreScrollOffset();
        }
        return;
      }
      final target = _pendingRestoreOffset!;
      final maxx = _scrollController.position.maxScrollExtent;
      if (maxx <= 0 && target > 0) {
        if (_restoreScrollAttemptsLeft > 0) {
          _restoreScrollAttemptsLeft--;
          _scheduleRestoreScrollOffset();
        }
        return;
      }
      _scrollController.jumpTo(target.clamp(0.0, maxx));
      _pendingRestoreOffset = null;
      _restoreScrollAttemptsLeft = 0;
    });
  }

  BottomNavigationBar _buildBottomNavigationBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      // On Home, highlight center Home tab (index 2).
      currentIndex: 2,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      selectedFontSize: 0,
      unselectedFontSize: 0,
      onTap: (index) {
        if (index == 0) {
          _navigateFromHome(const SearchPage());
          return;
        }
        if (index == 1) {
          _navigateFromHome(const FriendFeedPage());
          return;
        }
        if (index == 2) {
          return;
        }
        if (index == 3) {
          _navigateFromHome(const ActivityPage());
          return;
        }
        if (index == 4) {
          _navigateFromHome(const ProfilePage());
          return;
        }
      },
      items: MainBottomNavItems.barItems,
    );
  }

  @override
  void initState() {
    super.initState();
    _homeViewStateUserId = CurrentUserCache.instance.userId?.trim() ?? '';
    final viewSnap = HomeViewStateCache.instance.peek(_homeViewStateUserId);
    _scrollController = ScrollController(
      initialScrollOffset: viewSnap?.scrollOffset ?? 0.0,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hookNotificationsIfSignedIn());
    });
    // Banner: önbellekten (çıkışta temizlenir)
    for (final tab in [HomeTopPicksTab.weeklyLikes, HomeTopPicksTab.forYou]) {
      final cached = HomeTopPicksCache.peek(tab);
      if (cached != null && cached.isNotEmpty) {
        _topPicksByTab[tab] = List<ProductDto>.from(cached);
      }
    }
    // Ana grid: önce HomeFeedCache (disk + splash aynı API), yok eski SearchWarmCache.
    final homeSnap = HomeFeedCache.instance.peek();
    final warmTags = SearchWarmCache.instance.peekRootTags();
    if (viewSnap != null) {
      _tags = warmTags;
      _filteredProducts = List<ProductDto>.from(viewSnap.products);
      _currentPage = viewSnap.currentPage;
      _totalPages = viewSnap.totalPages;
      _totalElements = viewSnap.totalElements;
      _selectedCategoryIndex = viewSnap.selectedCategoryIndex;
      _selectedSubCategoryIndex = viewSnap.selectedSubCategoryIndex;
      _activeCategoryPathPrefix = viewSnap.activeCategoryPathPrefix;
      _activeSortOption = viewSnap.activeSortOption;
      _isBannerCollapsed = viewSnap.isBannerCollapsed;
      _isLoading = false;
      _isFiltering = false;
      _errorMessage = null;
      _pendingRestoreOffset = viewSnap.scrollOffset;
      _restoreScrollAttemptsLeft = 18;
      _scheduleRestoreScrollOffset();
      unawaited(_loadData(background: true, preserveLoadedProducts: true));
    } else if (homeSnap != null && homeSnap.content.isNotEmpty) {
      _tags = warmTags;
      _filteredProducts = List<ProductDto>.from(homeSnap.content);
      _currentPage = homeSnap.number;
      _totalPages = homeSnap.totalPages;
      _totalElements = homeSnap.totalElements;
      _isLoading = false;
      _isFiltering = false;
      _errorMessage = null;
      unawaited(_loadData(background: true));
    } else {
      final warmProducts = SearchWarmCache.instance.peekSeedProducts();
      if (warmTags.isNotEmpty || warmProducts.isNotEmpty) {
        _tags = warmTags;
        _filteredProducts = warmProducts;
        _isLoading = false;
        _isFiltering = false;
        _errorMessage = null;
        if (_filteredProducts.isNotEmpty) {
          _currentPage = 0;
          _totalPages = 1;
          _totalElements = _filteredProducts.length;
        }
        unawaited(_loadData(background: true));
      } else {
        _loadData();
      }
    }
    MessageUnreadService.instance.attach();
    unawaited(
      FollowingIdSetCache.instance.ensureLoaded(
        _interactionRepository,
        _authService,
        _sessionHelper,
      ),
    );
    _scrollController.addListener(_onScroll);
    unawaited(_hydrateFriendLikersFromDisk());
    FollowingIdSetCache.instance.addListener(_onFollowingChangedForFriendLikers);
    unawaited(_loadFriendLikers());
    unawaited(_warmSearchCatalogInBackground());
    registerProductCardGridResyncHandler(_onProductCardGridResync);
    _searchController.addListener(() {
      _onSearchChanged(_searchController.text);
    });
    _searchFocusNode.addListener(() {
      setState(() {});
    });
    _homeFeedPollTimer = Timer.periodic(
      AppBackgroundTimers.homeFeedBackgroundPoll,
      (_) {
        unawaited(_pollHomeFeedForUpdates());
        _friendFeedRefreshPollTick++;
        if (_friendFeedRefreshPollTick % 3 == 0) {
          unawaited(_loadFriendLikers());
        }
      },
    );
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
    _rememberHomeViewState();
    unregisterProductCardGridResyncHandler(_onProductCardGridResync);
    FollowingIdSetCache.instance.removeListener(_onFollowingChangedForFriendLikers);
    MessageUnreadService.instance.detach();
    if (_notificationSvcAttached) {
      NotificationRealtimeService.instance.detach();
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _homeFeedPollTimer?.cancel();
    super.dispose();
  }


  Future<void> _hydrateFriendLikersFromDisk() async {
    final uid = CurrentUserCache.instance.userId?.trim() ?? '';
    if (uid.isEmpty) return;
    final disk = await HomeFriendLikerPrefs.instance.loadMap(uid);
    if (!mounted || disk.isEmpty) return;
    setState(() {
      _friendLikersMap = _mergeFriendLikersMapsPreserve(_friendLikersMap, disk);
    });
  }

  Future<void> _persistFriendLikersMap() async {
    final uid = CurrentUserCache.instance.userId?.trim() ?? '';
    if (uid.isEmpty) return;
    if (_friendLikersMap.isEmpty) return;
    await HomeFriendLikerPrefs.instance.saveMap(uid, _friendLikersMap);
  }

  void _onFollowingChangedForFriendLikers() {
    if (!mounted) return;
    if (FollowingIdSetCache.instance.isReady) {
      setState(() {
        _friendLikersMap = _pruneFriendLikersMapByFollowing(_friendLikersMap);
      });
      unawaited(_persistFriendLikersMap());
    }
    unawaited(_loadFriendLikers());
    // Yeni takip: takip listesi API’si veya arkadaş feed’i birkaç sn gecikebilir.
    if (FollowingIdSetCache.instance.hasPendingOptimisticFollows) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        unawaited(_loadFriendLikers());
      });
    }
  }

  /// Baloncuk anahtarından aktör kullanıcı id (takip budaması + dedupe); saf `url:…` için null.
  String? _canonicalActorIdForBubbleKey(String key) {
    if (key.startsWith('uid:')) {
      final pipe = key.indexOf('|');
      final slice = pipe == -1 ? key.substring(4) : key.substring(4, pipe);
      final id = slice.trim();
      return id.isEmpty ? null : id;
    }
    if (key.startsWith('fallback:')) {
      final parts = key.split(':');
      if (parts.length >= 2) {
        final id = parts[1].trim();
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  String _bubbleDedupeSlot(String key) {
    final aid = _canonicalActorIdForBubbleKey(key);
    if (aid != null && aid.isNotEmpty) return 'a:$aid';
    return 'x:$key';
  }

  /// Aynı kullanıcı için `uid:…|` biçimini eski `url:` / `fallback:` üzerine tercih et.
  bool _bubbleKeyPreferNew(String incoming, String existing) {
    final i = incoming.startsWith('uid:');
    final e = existing.startsWith('uid:');
    if (i && !e) return true;
    if (!i && e) return false;
    return false;
  }

  bool _followingSnapshotContains(Set<String> following, String uidRaw) {
    final t = uidRaw.trim();
    if (t.isEmpty) return false;
    if (following.contains(t)) return true;
    final n = int.tryParse(t);
    if (n != null && following.contains(n.toString())) return true;
    return false;
  }

  Map<String, List<String>> _pruneFriendLikersMapByFollowing(
    Map<String, List<String>> input,
  ) {
    if (!FollowingIdSetCache.instance.isReady) return input;
    final following = FollowingIdSetCache.instance.snapshot;
    final out = <String, List<String>>{};
    for (final e in input.entries) {
      final kept = e.value.where((bubbleKey) {
        final uid = _canonicalActorIdForBubbleKey(bubbleKey);
        if (uid == null) return true;
        return _followingSnapshotContains(following, uid);
      }).toList();
      if (kept.isNotEmpty) {
        out[e.key] = kept;
      }
    }
    return out;
  }

  /// Loads friend feed from backend, populates the memory cache and
  /// immediately rebuilds [_friendLikersMap] so avatars show on first open.
  Future<void> _loadFriendLikers() async {
    try {
      const friendFeedPageSize = 80;
      final page0 = await _friendsFeedRepository.getFriendsFeed(
        page: 0,
        size: friendFeedPageSize,
      );
      if (!mounted) return;

      // Aynı üründe birden çok yorumcu + backend aynı [id]'yi farklı satırlarda tekrarlayabiliyor.
      final dtoById = <String, FriendsFeedItemDto>{};
      void ingestDtoPage(FriendsFeedPageDto p) {
        for (final e in p.content) {
          dtoById.putIfAbsent(_friendsFeedDtoDedupeKey(e), () => e);
        }
      }

      ingestDtoPage(page0);
      for (var p = 1; p < 5 && p < page0.totalPages; p++) {
        try {
          final pn = await _friendsFeedRepository.getFriendsFeed(
            page: p,
            size: friendFeedPageSize,
          );
          if (!mounted) return;
          ingestDtoPage(pn);
        } catch (_) {}
      }

      var items = activityItemsFromFriendsFeedDtos(dtoById.values);
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final existing = FriendFeedMemoryCache.instance.peek();
      final mergedByActivityId = <String, ActivityItem>{};
      for (final item in items) {
        mergedByActivityId.putIfAbsent(
          _friendLikerActivityMergeKey(item),
          () => item,
        );
      }
      for (final item in existing?.items ?? const <ActivityItem>[]) {
        mergedByActivityId.putIfAbsent(
          _friendLikerActivityMergeKey(item),
          () => item,
        );
      }
      final mergedList = mergedByActivityId.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _friendFeedItemsForLikers = mergedList;
      FriendFeedMemoryCache.instance.remember(
        items: mergedList,
        page: page0.number,
        totalPages: page0.totalPages,
      );

      if (!mounted) return;

      final fresh = _buildFriendLikersMapForItems(mergedList);
      setState(() {
        var next = _mergeFriendLikersMapsPreserve(_friendLikersMap, fresh);
        next = _pruneFriendLikersMapByFollowing(next);
        _friendLikersMap = next;
      });
      unawaited(_persistFriendLikersMap());
      unawaited(_supplementFriendLikersFromFollowedReviews());
    } catch (_) {
      // Friend likers are optional — silent fail.
      if (!mounted) return;
      if (_friendLikersMap.isEmpty) {
        setState(() {
          final fresh =
              _buildFriendLikersMapForItems(_friendFeedItemsForLikers);
          var next = _mergeFriendLikersMapsPreserve(_friendLikersMap, fresh);
          next = _pruneFriendLikersMapByFollowing(next);
          _friendLikersMap = next;
        });
        unawaited(_persistFriendLikersMap());
      }
      unawaited(_supplementFriendLikersFromFollowedReviews());
    }
  }

  /// Pull-to-refresh / tam yenilemede: kart in-memory sayaçları + key ile yeniden mount;
  /// askıdaki yorum sonrası yıldız ve review sayısı API ile hizalansın.
  void _bumpProductCardCachesForListedProductIds() {
    final ids = <String>{};
    for (final p in _filteredProducts) {
      final id = p.id.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    for (final p in _searchResults) {
      final id = p.id.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    for (final tab in HomeTopPicksTab.values) {
      for (final p in _topPicksByTab[tab]!) {
        final id = p.id.trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }
    for (final id in ids) {
      // Sayaç cache'ini koru: tab dönüşünde 0 -> gerçek değer flash'ı oluşmasın.
      _productCardResync[id] = (_productCardResync[id] ?? 0) + 1;
    }
  }

  /// API sayfa 0 yenilendiğinde eski ürün→avatar eşlemesini korur (sıra değişince kaybolmayı önler).
  Map<String, List<String>> _mergeFriendLikersMapsPreserve(
    Map<String, List<String>> previous,
    Map<String, List<String>> fresh,
  ) {
    final ids = <String>{...previous.keys, ...fresh.keys};
    final out = <String, List<String>>{};
    for (final id in ids) {
      final merged = _mergeOrderedFriendAvatarKeys(fresh[id], previous[id]);
      if (merged.isNotEmpty) {
        out[id] = merged;
      }
    }
    return out;
  }

  List<String> _mergeOrderedFriendAvatarKeys(
    List<String>? primary,
    List<String>? fallback,
  ) {
    final slotOrder = <String>[];
    final slotToKey = <String, String>{};

    void consider(String k) {
      final slot = _bubbleDedupeSlot(k);
      if (slotToKey.containsKey(slot)) {
        final cur = slotToKey[slot]!;
        if (_bubbleKeyPreferNew(k, cur)) {
          slotToKey[slot] = k;
        }
        return;
      }
      if (slotOrder.length >= _kMaxFriendLikerKeysPerProduct) {
        return;
      }
      slotToKey[slot] = k;
      slotOrder.add(slot);
    }

    for (final k in [...?primary, ...?fallback]) {
      consider(k);
    }
    return [for (final s in slotOrder) slotToKey[s]!];
  }

  /// Arkadaş feed’indeki review aktiviteleri → ürün id → avatar anahtarları (tarih sırası).
  /// Takip budaması ayrıca [_pruneFriendLikersMapByFollowing] ile uygulanır.
  Map<String, List<String>> _buildFriendLikersMapForItems(
    Iterable<ActivityItem> source,
  ) {
    final map = <String, List<String>>{};
    final seenKeysByProduct = <String, Set<String>>{};
    for (final item in source) {
      if (item.isActorInactive) continue;
      if (item.type != ActivityType.review) {
        continue;
      }
      final productId = item.targetContent?.productId?.trim();
      if (productId == null || productId.isEmpty) continue;
      final list = map.putIfAbsent(productId, () => <String>[]);
      if (list.length >= _kMaxFriendReviewBubblesPerProduct) continue;

      final avatarKey = _friendAvatarKeyFor(item.user);
      final uid = item.user.id.trim();
      final seen = seenKeysByProduct.putIfAbsent(productId, () => <String>{});
      final dedupeKey = uid.isNotEmpty ? 'uid:$uid' : avatarKey;
      if (seen.contains(dedupeKey)) continue;
      seen.add(dedupeKey);
      list.add(avatarKey);
    }
    return map.map(
      (k, v) => MapEntry(
        k,
        _mergeOrderedFriendAvatarKeys(v, null),
      ),
    );
  }

  /// ProductCard'e avatar verisini taşır:
  /// - `uid:<id>|url:<raw>`: takip kümesiyle budama + dedupe için stabil kullanıcı.
  /// - `uid:<id>|fallback:<initial>` / `fallback:<userId>:<initial>`: resim yok.
  String _friendAvatarKeyFor(ActivityUser user) {
    final uid = user.id.trim();
    final uidPrefix = uid.isNotEmpty ? 'uid:$uid|' : '';
    final raw = user.avatarUrl?.trim();
    if (raw != null && raw.isNotEmpty) {
      return '${uidPrefix}url:$raw';
    }
    final trimmed = user.username.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    if (uid.isNotEmpty) {
      return '${uidPrefix}fallback:$initial';
    }
    return 'fallback::$initial';
  }

  String _friendAvatarKeyFromReview(ReviewDto r) {
    final uid = r.ownerId.trim();
    final uidPrefix = uid.isNotEmpty ? 'uid:$uid|' : '';
    final raw = r.ownerProfilePhotoUrl?.trim();
    if (raw != null && raw.isNotEmpty) {
      return '${uidPrefix}url:$raw';
    }
    final trimmed = r.ownerUserName.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    if (uid.isNotEmpty) {
      return '${uidPrefix}fallback:$initial';
    }
    return 'fallback::$initial';
  }

  /// GET /api/reviews/product/{id} — takip edilen yorum sahipleri (ürün başına en fazla 5).
  Map<String, List<String>> _buildFriendLikersMapFromFollowedProductReviews(
    Set<String> following,
    Map<String, List<ReviewDto>> reviewsByProduct,
  ) {
    final me = CurrentUserCache.instance.userId?.trim() ?? '';
    final map = <String, List<String>>{};
    for (final e in reviewsByProduct.entries) {
      final pid = e.key.trim();
      if (pid.isEmpty) continue;
      final rows = List<ReviewDto>.from(e.value)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final keys = <String>[];
      final seenUid = <String>{};
      for (final r in rows) {
        if (!isReviewEntityVisible(r)) continue;
        final oid = r.ownerId.trim();
        if (oid.isEmpty || oid == me) continue;
        if (!_followingSnapshotContains(following, oid)) continue;
        if (seenUid.contains(oid)) continue;
        seenUid.add(oid);
        keys.add(_friendAvatarKeyFromReview(r));
        if (keys.length >= _kMaxFriendReviewBubblesPerProduct) break;
      }
      if (keys.isNotEmpty) {
        map[pid] = _mergeOrderedFriendAvatarKeys(keys, null);
      }
    }
    return map;
  }

  List<String> _orderedProductIdsForFriendReviewSupplement() {
    final out = <String>[];
    final seen = <String>{};
    void take(Iterable<ProductDto> products) {
      for (final p in products) {
        final id = p.id.trim();
        if (id.isEmpty || seen.contains(id)) continue;
        if (out.length >= _kFriendReviewSupplementMaxProducts) return;
        seen.add(id);
        out.add(id);
      }
    }

    take(_filteredProducts);
    for (final tab in HomeTopPicksTab.values) {
      take(_topPicksByTab[tab]!);
    }
    return out;
  }

  /// Feed penceresine sığmayan takip edilen yorumcuları ürün yorum listesinden tamamla.
  Future<void> _supplementFriendLikersFromFollowedReviews({bool force = false}) async {
    if (!mounted) return;
    final now = DateTime.now();
    if (!force &&
        _friendReviewSupplementCooldownUntil != null &&
        now.isBefore(_friendReviewSupplementCooldownUntil!)) {
      return;
    }
    final req = ++_friendReviewSupplementRequestId;
    final token = await _sessionHelper.ensureSession();
    if (token == null || !mounted || req != _friendReviewSupplementRequestId) return;

    await FollowingIdSetCache.instance.ensureLoaded(
      _interactionRepository,
      _authService,
      _sessionHelper,
    );
    if (!mounted || req != _friendReviewSupplementRequestId) return;
    if (!FollowingIdSetCache.instance.isReady) return;
    final following = FollowingIdSetCache.instance.snapshot;
    if (following.isEmpty) return;

    final orderedIds = _orderedProductIdsForFriendReviewSupplement();
    if (orderedIds.isEmpty) return;

    final reviewsByProduct = <String, List<ReviewDto>>{};
    for (var i = 0; i < orderedIds.length; i += _kFriendReviewSupplementConcurrency) {
      if (!mounted || req != _friendReviewSupplementRequestId) return;
      final chunk = orderedIds.skip(i).take(_kFriendReviewSupplementConcurrency).toList();
      final batch = await Future.wait(
        chunk.map((pid) async {
          try {
            final list = await _reviewRepository
                .getReviewsByProductIdForFriendCardOverlay(
              pid,
              firebaseIdToken: token,
            );
            return MapEntry(pid, list);
          } catch (_) {
            return MapEntry(pid, <ReviewDto>[]);
          }
        }),
      );
      for (final e in batch) {
        reviewsByProduct[e.key] = e.value;
      }
    }

    if (!mounted || req != _friendReviewSupplementRequestId) return;
    final supplement = _buildFriendLikersMapFromFollowedProductReviews(
      following,
      reviewsByProduct,
    );
    if (supplement.isEmpty) return;

    if (!force) {
      _friendReviewSupplementCooldownUntil =
          DateTime.now().add(_kFriendReviewSupplementMinGap);
    }

    setState(() {
      final next = <String, List<String>>{};
      final keys = {..._friendLikersMap.keys, ...supplement.keys};
      for (final pid in keys) {
        final merged = _mergeOrderedFriendAvatarKeys(
          _friendLikersMap[pid],
          supplement[pid],
        );
        if (merged.isEmpty) continue;
        next[pid] = merged;
      }
      _friendLikersMap = _pruneFriendLikersMapByFollowing(next);
    });
    unawaited(_persistFriendLikersMap());
  }

  /// Search sayfasıyla aynı: GET /api/products tüm ürün listesi (önbellek + arka planda ısıtma).
  Future<void> _warmSearchCatalogInBackground() async {
    if (_fullSearchCatalog.isNotEmpty || _fullSearchCatalogFuture != null) return;
    try {
      _fullSearchCatalogFuture = _productRepository.getAllProductsRaw();
      final products = await _fullSearchCatalogFuture!;
      if (products.isNotEmpty) {
        _fullSearchCatalog = products;
        SearchWarmCache.instance.rememberSeedProducts(products);
      }
    } catch (_) {}
    finally {
      _fullSearchCatalogFuture = null;
    }
  }

  Future<List<ProductDto>> _ensureSearchCatalog() async {
    if (_fullSearchCatalog.isNotEmpty) return _fullSearchCatalog;
    if (_fullSearchCatalogFuture != null) {
      final inFlight = await _fullSearchCatalogFuture!;
      if (inFlight.isNotEmpty) _fullSearchCatalog = inFlight;
      return inFlight;
    }
    _fullSearchCatalogFuture = _productRepository.getAllProductsRaw();
    try {
      final products = await _fullSearchCatalogFuture!;
      if (products.isNotEmpty) {
        _fullSearchCatalog = products;
        SearchWarmCache.instance.rememberSeedProducts(products);
      }
      return products;
    } catch (_) {
      // Ağ hatasında warm cache fallback (varsa yine arama çalışsın).
      final warm = SearchWarmCache.instance.peekSeedProducts();
      return warm;
    } finally {
      _fullSearchCatalogFuture = null;
    }
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    _searchDebounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _isSearchLoading = false;
      });
      return;
    }
    // Yazmaya başlar başlamaz banner/active-header kaybolsun.
    setState(() {
      _searchQuery = q;
      _isSearchLoading = true;
      _activeBannerTab = null;
    });
    final req = ++_searchReqSeq;
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_runHomeSearch(q, req));
    });
  }

  /// [SearchPage] ile aynı eşleme: ürün adı, etiket adı, kategori path parçaları.
  Future<void> _runHomeSearch(String normalizedQuery, int req) async {
    if (!mounted || req != _searchReqSeq) return;
    setState(() {
      _searchQuery = normalizedQuery;
      _isSearchLoading = true;
    });
    try {
      final pool = await _ensureSearchCatalog();
      if (!mounted || req != _searchReqSeq) return;
      final results = pool.where((product) {
        final productName = product.name.toLowerCase();
        final tagName = product.tag.name.toLowerCase();
        final tagPathSegments = (product.tag.categoryPath ?? '')
            .toLowerCase()
            .split('.')
            .where((segment) => segment.isNotEmpty)
            .toList();
        final nameMatch = productName.contains(normalizedQuery);
        final ownTagMatch = tagName.contains(normalizedQuery) ||
            tagPathSegments.any(
              (segment) => segment.contains(normalizedQuery),
            );
        return nameMatch || ownTagMatch;
      }).toList();
      if (!mounted || req != _searchReqSeq) return;
      setState(() {
        _searchResults = results;
        _isSearchLoading = false;
      });
    } catch (_) {
      if (!mounted || req != _searchReqSeq) return;
      setState(() {
        _isSearchLoading = false;
        _searchResults = [];
      });
    }
  }

  Future<void> _onBannerTap(HomeTopPicksTab tab) async {
    if (_activeBannerTab == tab) {
      setState(() => _activeBannerTab = null);
      return;
    }
    setState(() => _activeBannerTab = tab);
    final cached = _topPicksByTab[tab] ?? [];
    if (cached.isEmpty) {
      await _loadTopPicksForTab(tab);
    }
  }

  Future<void> _loadTopPicksForTab(HomeTopPicksTab tab) async {
    if (_topPicksLoadingTabs.contains(tab)) return;
    final requestId = ++_topPicksRequestSeq;
    _topPicksLatestRequestByTab[tab] = requestId;
    _topPicksLoadingTabs.add(tab);
    if (mounted) setState(() {});
    try {
      final firebaseIdToken = await _sessionHelper.ensureSession();
      late ProductSearchResultDto result;
      switch (tab) {
        case HomeTopPicksTab.weeklyLikes:
          result = await _productRepository
              .getTrendingLikesWeekFeed(
                page: 0,
                size: 10,
                firebaseIdToken: firebaseIdToken,
              )
              .timeout(const Duration(seconds: 8));
          break;
        case HomeTopPicksTab.forYou:
          if (firebaseIdToken == null) {
            result = await _productRepository
                .getTrendingReviewsFeed(page: 0, size: 10, firebaseIdToken: null)
                .timeout(const Duration(seconds: 8));
          } else {
            try {
              result = await _productRepository
                  .getPersonalizedFeed(
                    page: 0,
                    size: 10,
                    firebaseIdToken: firebaseIdToken,
                  )
                  .timeout(const Duration(seconds: 8));
            } catch (_) {
              result = await _productRepository
                  .getTrendingReviewsFeed(
                    page: 0,
                    size: 10,
                    firebaseIdToken: firebaseIdToken,
                  )
                  .timeout(const Duration(seconds: 8));
            }
          }
          break;
      }
      if (!mounted || _topPicksLatestRequestByTab[tab] != requestId) return;
      final products = result.content.take(10).toList();
      // Kartlar render olmadan sosyal sayaclari cache'e yaz: 0 -> gercek deger flash olmasin.
      await _warmProductCardSocialCaches(
        products,
        firebaseIdToken,
        triggerResync: false,
      );
      if (!mounted || _topPicksLatestRequestByTab[tab] != requestId) return;
      HomeTopPicksCache.remember(tab, products);
      setState(() => _topPicksByTab[tab] = products);
    } catch (_) {
      // silently fail
    } finally {
      _topPicksLoadingTabs.remove(tab);
      if (mounted) setState(() {});
    }
  }

  Future<void> _warmProductCardSocialCaches(
    List<ProductDto> products,
    String? firebaseIdToken,
    {bool triggerResync = true}
  ) async {
    if (products.isEmpty) return;
    final visible = products.take(10).toList();
    for (final p in visible) {
      try {
        final futures = await Future.wait([
          _interactionRepository.getProductLikeCount(p.id),
          _reviewRepository.getReviewsByProductId(
            p.id,
            firebaseIdToken: firebaseIdToken,
          ),
        ]);
        final likeCount = futures[0] as int;
        final reviews = filterVisibleReviews(futures[1] as List<ReviewDto>);
        final reviewCount = reviews.length;
        final sum = reviews.fold<int>(0, (acc, r) => acc + r.rating);
        final rating = reviewCount > 0 ? (sum / reviewCount) : 0.0;
        setProductCardSocialCaches(
          p.id,
          likeCount: likeCount,
          reviewCount: reviewCount,
          rating: rating,
          hasPhotoReview: anyVisibleReviewHasPhoto(reviews),
        );
      } catch (_) {
        // Sessiz: kart kendi akışında tekrar dener.
      }
    }
    if (!mounted || !triggerResync) return;
    setState(() {
      for (final p in visible) {
        final id = p.id.trim();
        if (id.isEmpty) continue;
        _productCardResync[id] = (_productCardResync[id] ?? 0) + 1;
      }
    });
  }

  /// Infinite scroll: listenere yaklaşınca sonraki sayfayı yükle
  void _onScroll() {
    final hasClients = _scrollController.hasClients;
    final shouldShow =
        hasClients && _scrollController.offset > _kScrollToTopThreshold;
    if (shouldShow != _showScrollToTop && mounted) {
      setState(() {
        _showScrollToTop = shouldShow;
      });
    }

    if (_isFiltering || _isLoadingMore || _filteredProducts.isEmpty) return;
    if (_currentPage + 1 >= _totalPages) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMoreProducts();
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || _currentPage + 1 >= _totalPages) return;
    setState(() {
      _isLoadingMore = true;
    });
    await _loadProductsPage(_currentPage + 1, append: true);
    if (mounted) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  /// Aynı API ile ilk sayfayı tekrar yükleyip, değişiklik varsa listeyi günceller (yeni ürün, sıra, toplam).
  Future<void> _pollHomeFeedForUpdates() async {
    if (!mounted) return;
    if (_activeCategoryPathPrefix != null) return;
    if (_activeBannerTab != null) return;
    if (_searchQuery.trim().isNotEmpty) return;
    if (_isLoading || _isLoadingMore || _homeFeedPollInFlight) return;

    _homeFeedPollInFlight = true;
    try {
      final token = await _sessionHelper.ensureSession();
      if (!mounted) return;

      final result = await _productRepository.getHomeFeed(
        page: 0,
        size: 10,
        firebaseIdToken: token,
        sortBy: _activeSortOption.apiValue,
      );
      if (!mounted) return;

      if (_activeSortOption == FeedSortOption.newest &&
          _homeFeedFirstPageUnchanged(result)) {
        return;
      }

      // Aşağıdayken yeni ürün gelse bile listenin başı zıplamasın
      final savedOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;
      const keepScrollThreshold = 32.0;

      final mergedProducts = _mergePolledFirstPageKeepLoadedItems(
        result.content,
      );
      final mergedWithOverrides = _applyHomeLikeOverrides(mergedProducts);
      if (!mounted) return;
      setState(() {
        _filteredProducts = mergedWithOverrides;
        _currentPage = mergedWithOverrides.length > result.content.length
            ? _currentPage
            : result.number;
        _totalPages = result.totalPages;
        _totalElements = result.totalElements;
        _isFiltering = false;
      });
      if (savedOffset > keepScrollThreshold) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final maxx = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(savedOffset.clamp(0.0, maxx));
        });
      }
      HomeFeedCache.instance.setFromResult(result);
      ReviewPrefetchService.instance.prefetchForProducts(
        _filteredProducts,
        maxCount: 8,
      );
    } catch (_) {
      // Sessiz — arka plan tazeleme
    } finally {
      _homeFeedPollInFlight = false;
    }
  }

  /// [getHomeFeed] ilk sayfa ile mevcut gridin başı aynı mı, toplam adet aynı mı?
  bool _homeFeedFirstPageUnchanged(ProductSearchResultDto result) {
    if (result.totalElements != _totalElements) return false;
    final next = result.content;
    if (next.isEmpty) return _filteredProducts.isEmpty;
    final n = next.length;
    if (_filteredProducts.length < n) return false;
    for (var i = 0; i < n; i++) {
      if (next[i].id != _filteredProducts[i].id) return false;
    }
    return true;
  }

  /// Ürün listesi artık token olmadan da çalışır (backend 200 döner).
  /// - All: /api/products/home?page=X&size=Y
  /// - Category: /api/products/search?categoryPathPrefix=...&page=X&size=Y
  /// [append]: true ise gelen sayfa mevcut listeye eklenir (infinite scroll)
  Future<void> _loadProductsPage(int page, {bool append = false}) async {
    try {
      final firebaseIdToken = await _sessionHelper.ensureSession();

      late ProductSearchResultDto result;
      if (_activeCategoryPathPrefix != null) {
        result = await _productRepository.searchProducts(
          categoryPathPrefix: _activeCategoryPathPrefix!,
          page: page,
          size: 10,
          firebaseIdToken: firebaseIdToken,
          sortBy: _activeSortOption.apiValue,
        );
      } else {
        result = await _productRepository.getHomeFeed(
          page: page,
          size: 10,
          firebaseIdToken: firebaseIdToken,
          sortBy: _activeSortOption.apiValue,
        );
      }

      final nextProducts =
          (append && page > 0)
              ? [..._filteredProducts, ...result.content]
              : result.content;
      final nextWithOverrides = _applyHomeLikeOverrides(nextProducts);

      if (!mounted) return;

      setState(() {
        _filteredProducts = nextWithOverrides;
        _currentPage = result.number;
        _totalPages = result.totalPages;
        _totalElements = result.totalElements;
        _isFiltering = false;
      });
      _scheduleRestoreScrollOffset();

      if (!append &&
          _activeCategoryPathPrefix == null) {
        HomeFeedCache.instance.setFromResult(result);
      }

      // Ana sayfa feed'ini [SearchWarmCache] üzerine yazma — inline arama tüm katalogu kullansın.

      // Trendyol-style warmup: prefetch reviews for likely-to-open products.
      ReviewPrefetchService.instance.prefetchForProducts(
        append && page > 0 ? result.content : _filteredProducts,
        maxCount: append ? 5 : 8,
      );
      if (mounted) {
        unawaited(_supplementFriendLikersFromFollowedReviews(force: append));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFiltering = false;
        _filteredProducts = [];
      });
      CustomSnackBar.show(
        context,
        message:
            'Failed to load products: ${ErrorHandler.getUserFriendlyMessage(e)}',
        variant: CustomSnackBarVariant.error,
        duration: const Duration(seconds: 3),
      );
    }
  }

  List<ProductDto> _mergePolledFirstPageKeepLoadedItems(List<ProductDto> firstPage) {
    // Polling should refresh top rows but never throw away already loaded pages.
    if (_filteredProducts.isEmpty || _filteredProducts.length <= firstPage.length) {
      return firstPage;
    }

    final firstIds = firstPage.map((p) => p.id).toSet();
    final tail = _filteredProducts.where((p) => !firstIds.contains(p.id)).toList();
    return [...firstPage, ...tail];
  }


  Future<void> _onRootCategoryTap(TagDto rootTag, int rootIndex) async {
    setState(() {
      _selectedCategoryIndex = rootIndex;
      _selectedSubCategoryIndex = -1;
      _subTags = [];
      _isLoadingSubTags = true;
      _isFiltering = true;
      _activeCategoryPathPrefix = rootTag.categoryPath;
      _isBannerCollapsed = true;
    });

    // Alt kategorileri arka planda getir; ürün listesi bloklanmasın.
    unawaited(_loadSubTagsForRoot(rootTag));

    await _loadProductsPage(0);
  }

  Future<void> _loadSubTagsForRoot(TagDto rootTag) async {
    try {
      final token = await _sessionHelper.ensureSession();
      TagChildrenResponse childrenResponse;
      try {
        childrenResponse = await _tagRepository.getTagChildren(rootTag.id, token);
      } catch (_) {
        childrenResponse = await _tagRepository.getTagChildren(rootTag.id, null);
      }
      if (!mounted) return;
      setState(() {
        _subTags = childrenResponse.children;
        _isLoadingSubTags = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSubTags = false;
        _subTags = [];
      });
    }
  }

  Widget _buildProductGrid() {
    // Öncelik her zaman arama sonucu: banner tab açık olsa bile arama kazanır.
    if (_searchQuery.isNotEmpty) {
      if (_isSearchLoading) {
        return const Center(
          child: ListLoadMoreSkeleton(),
        );
      }
      if (_searchResults.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxLarge),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off_rounded, size: 48, color: AppColors.border),
                const SizedBox(height: 12),
                Text(
                  'No results for "$_searchQuery"',
                  style: AppTextStyles.bodySecondary,
                  textAlign: TextAlign.center,
                ),
                const ProductRequestNotice(),
              ],
            ),
          ),
        );
      }
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppSpacing.xLarge,
          mainAxisSpacing: AppSpacing.xLarge,
          childAspectRatio: 0.57,
        ),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final product = _searchResults[index];
          return ProductCard(
            key: ValueKey('search_${product.id}_${_productCardResync[product.id] ?? 0}'),
            productId: product.id,
            imageUrl: product.imageURL,
            title: product.name,
            category: product.tag.name,
            categoryPath: product.tag.categoryPath,
            rating: product.averageRating ?? 0.0,
            desc: product.description ?? '',
            isFavorite: _effectiveHomeLiked(product),
            loadReviewCount: true,
            friendAvatarUrls: _friendLikersMap[product.id] ?? const [],
            onTap: () async {
              final r = await Navigator.push<ReviewPagePopResult?>(
                context,
                SlideRightRoute(page: ReviewPage(product: product)),
              );
              if (!mounted) return;
              if (r != null) {
                _applyProductFromReviewExit(r);
              } else {
                unawaited(_refreshProductLikeStatus(product.id));
              }
            },
            onFavoriteTap: () async {
              await _toggleHomeProductLike(product);
            },
          );
        },
      );
    }

    // ── Banner tab products — full grid below the header ───────────────────
    if (_activeBannerTab != null) {
      final tab = _activeBannerTab!;
      final products = _topPicksByTab[tab] ?? [];
      final isLoading = _topPicksLoadingTabs.contains(tab);
      if (isLoading && products.isEmpty) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: AppSpacing.xLarge,
            mainAxisSpacing: AppSpacing.xLarge,
            childAspectRatio: 0.57,
          ),
          itemCount: 4,
          itemBuilder: (_, __) => const ProductCardSkeleton(),
        );
      }
      if (products.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxLarge),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('No products found', style: AppTextStyles.bodySecondary),
                const ProductRequestNotice(),
              ],
            ),
          ),
        );
      }
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppSpacing.xLarge,
          mainAxisSpacing: AppSpacing.xLarge,
          childAspectRatio: 0.57,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return ProductCard(
            key: ValueKey('banner_${product.id}_${_productCardResync[product.id] ?? 0}'),
            productId: product.id,
            imageUrl: product.imageURL,
            title: product.name,
            category: product.tag.name,
            categoryPath: product.tag.categoryPath,
            rating: product.averageRating ?? 0.0,
            desc: product.description ?? '',
            isFavorite: _effectiveHomeLiked(product),
            loadReviewCount: true,
            friendAvatarUrls: _friendLikersMap[product.id] ?? const [],
            onTap: () async {
              final r = await Navigator.push<ReviewPagePopResult?>(
                context,
                SlideRightRoute(page: ReviewPage(product: product)),
              );
              if (!mounted) return;
              if (r != null) {
                _applyProductFromReviewExit(r);
              } else {
                unawaited(_refreshProductLikeStatus(product.id));
              }
            },
            onFavoriteTap: () async {
              await _toggleHomeProductLike(product);
            },
          );
        },
      );
    }

    if (_isFiltering) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppSpacing.xLarge,
          mainAxisSpacing: AppSpacing.xLarge,
          childAspectRatio: 0.57,
        ),
        itemCount: 4,
        itemBuilder: (context, index) => const ProductCardSkeleton(),
      );
    }
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxLarge),
          child: Text('No products found', style: AppTextStyles.bodySecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: AppSpacing.xLarge,
            mainAxisSpacing: AppSpacing.xLarge,
            childAspectRatio: 0.57,
          ),
          itemCount: _filteredProducts.length,
          itemBuilder: (context, index) {
            final product = _filteredProducts[index];
            return ProductCard(
              key: ValueKey('pc_${product.id}_${_productCardResync[product.id] ?? 0}'),
              productId: product.id,
              imageUrl: product.imageURL,
              title: product.name,
              category: product.tag.name,
              categoryPath: product.tag.categoryPath,
              rating: product.averageRating ?? 0.0,
              desc: product.description ?? '',
              isFavorite: _effectiveHomeLiked(product),
              loadReviewCount: true,
              friendAvatarUrls: _friendLikersMap[product.id] ?? const [],
              onTap: () async {
                final r = await Navigator.push<ReviewPagePopResult?>(
                  context,
                  SlideRightRoute(page: ReviewPage(product: product)),
                );
                if (!mounted) return;
                if (r != null) {
                  _applyProductFromReviewExit(r);
                } else {
                  await _refreshProductLikeStatus(product.id);
                }
              },
              onFavoriteTap: () async {
                await _toggleHomeProductLike(product);
              },
            );
          },
        ),
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.large),
            child: Center(child: ListLoadMoreSkeleton()),
          )
        else if (_totalElements > _filteredProducts.length)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.small),
            child: Text(
              '${_filteredProducts.length} / $_totalElements',
              style: AppTextStyles.bodySecondary,
            ),
          ),
      ],
    );
  }

  /// Wraps the banner with an AnimatedContainer that collapses to a pill when
  /// a category is selected, and expands back when tapped or category deselected.
  /// Banner wrapper: animates between full carousel and a thin strip
  /// using AnimatedContainer (Curves.fastOutSlowIn, 500 ms) — tap strip to expand.
  Widget _buildAnimatedBanner() {
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 500),
        curve: Curves.fastOutSlowIn,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _isBannerCollapsed
              ? _buildThinBannerStrip()
              : _buildBannerArea(),
        ),
      ),
    );
  }

  /// Thin glowing strip shown while a category is active.
  /// Tapping it re-expands the banner.
  Widget _buildThinBannerStrip() {
    return GestureDetector(
      key: const ValueKey('thin_strip'),
      onTap: () => setState(() => _isBannerCollapsed = false),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
        child: Container(
          height: 5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary,
                AppColors.primary.withValues(alpha: 0.4),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBannerArea() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _activeBannerTab != null
            ? _buildBannerActiveHeader()
            : _BannerCarousel(
                key: const ValueKey('banner_carousel'),
                onBannerTap: _onBannerTap,
              ),
      ),
    );
  }

  /// Full-width banner card shown when a banner tab is active.
  Widget _buildBannerActiveHeader() {
    final tab = _activeBannerTab!;
    final isLiked = tab == HomeTopPicksTab.weeklyLikes;
    final label = isLiked ? 'Most Liked' : 'For You';
    final subtitle = isLiked
        ? 'Most loved products this week'
        : 'Picked just for your taste';
    final icon = isLiked ? Icons.favorite_rounded : Icons.auto_awesome_rounded;
    final gradientColors = isLiked
        ? [const Color(0xFF8B0000), AppColors.primary]
        : [const Color(0xFF3A1078), const Color(0xFF7B2FBE)];

    return Container(
      key: ValueKey(tab),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 110,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradientColors.last.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative background circles
          Positioned(
            right: -18,
            top: -18,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            right: 30,
            bottom: -30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon badge
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                // Label + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                // Close button
                GestureDetector(
                  onTap: () => setState(() => _activeBannerTab = null),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchChanged,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText: 'Search products, categories, or brands',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              textInputAction: TextInputAction.search,
              cursorColor: AppColors.primary,
              cursorWidth: 1.5,
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                _onSearchChanged('');
                _searchFocusNode.unfocus();
              },
              child: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.close_rounded,
                    color: AppColors.textSecondary, size: 20),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection() {
    if (_tags.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Categories',
            style: AppTextStyles.heading2.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 95,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _tags.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, tagIndex) {
              final tag = _tags[tagIndex];
              final selected = _selectedCategoryIndex == tagIndex;
              return _CircleCategoryItem(
                label: tag.name,
                isSelected: selected,
                onTap: () async {
                  if (selected) {
                    setState(() {
                      _selectedCategoryIndex = -1;
                      _selectedSubCategoryIndex = -1;
                      _subTags = [];
                      _activeCategoryPathPrefix = null;
                      _isFiltering = true;
                      _isBannerCollapsed = false;
                    });
                    await _loadProductsPage(0);
                  } else {
                    setState(() {
                      _activeBannerTab = null;
                      _isBannerCollapsed = true;
                    });
                    await _onRootCategoryTap(tag, tagIndex);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubCategoryRow() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _selectedCategoryIndex == -1
          ? const SizedBox.shrink()
          : _buildSubCategoryPanel(),
    );
  }

  Widget _buildSubCategoryPanel() {
    final selectedTag = _tags[_selectedCategoryIndex];
    final style = _categoryStyle(selectedTag.name);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: style.bgColor.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 9),
            // ── Sub-category chips ──
            if (_isLoadingSubTags)
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (_, __) => const SkeletonLoader(
                    width: 66,
                    height: 28,
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                ),
              )
            else if (_subTags.isNotEmpty)
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  itemCount: _subTags.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return _SubChip(
                        title: 'All',
                        selected: _selectedSubCategoryIndex == -1,
                        iconColor: style.iconColor,
                        onTap: () async {
                          final rootTag = _tags[_selectedCategoryIndex];
                          setState(() {
                            _selectedSubCategoryIndex = -1;
                            _activeCategoryPathPrefix = rootTag.categoryPath;
                            _isFiltering = true;
                          });
                          await _loadProductsPage(0);
                        },
                      );
                    }
                    final subIndex = i - 1;
                    final subTag = _subTags[subIndex];
                    return _SubChip(
                      title: subTag.name,
                      selected: subIndex == _selectedSubCategoryIndex,
                      iconColor: style.iconColor,
                      onTap: () async {
                        setState(() {
                          _selectedSubCategoryIndex = subIndex;
                          _activeCategoryPathPrefix = subTag.categoryPath;
                          _isFiltering = true;
                        });
                        await _loadProductsPage(0);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 9),
          ],
        ),
      ),
    );
  }

  Widget _buildSortBar() {
    if (_activeBannerTab != null || _searchQuery.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12, top: 0, bottom: 0),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: PopupMenuButton<FeedSortOption>(
          color: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: AppColors.border.withValues(alpha: 0.35),
            ),
          ),
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          tooltip: 'Sort feed',
          padding: EdgeInsets.zero,
          // [PopupMenuButton.constraints] applies to the *menu* overlay, not the
          // trigger child. Never use a tight maxHeight here — it would clip the
          // list to a single thin strip.
          onSelected: (v) async {
            if (v == _activeSortOption) return;
            setState(() {
              _activeSortOption = v;
              _isFiltering = true;
            });
            await _loadProductsPage(0);
          },
          // Menu width: explicitly wider than the small trigger pill (Flutter
          // otherwise sizes the overlay to the invoker, which looks cramped).
          menuPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
          itemBuilder: (context) {
            final w = MediaQuery.sizeOf(context).width;
            final menuItemWidth = (w - 32).clamp(248.0, 320.0);
            return FeedSortOption.values.map((o) {
              final selected = o == _activeSortOption;
              return PopupMenuItem<FeedSortOption>(
                value: o,
                height: 46,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  width: menuItemWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Icon(
                          _sortOptionIcon(o),
                          size: 19,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            o.label,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 14.5,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            constraints: const BoxConstraints(minHeight: 30, maxHeight: 32),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sort_rounded,
                  size: 16,
                  color: AppColors.textSecondary.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 108),
                  child: Text(
                    _activeSortOption.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 1),
                Icon(
                  Icons.expand_more_rounded,
                  size: 15,
                  color: AppColors.textSecondary.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _sortOptionIcon(FeedSortOption option) => switch (option) {
        FeedSortOption.newest => Icons.schedule_rounded,
        FeedSortOption.ratingDesc => Icons.star_rounded,
        FeedSortOption.reviewsDesc => Icons.chat_bubble_rounded,
      };

  /// [ReviewPage] dönüşünde grid, sayı ve favori durumu anında (flash’sız) güncellenir.
  void _applyProductFromReviewExit(ReviewPagePopResult r) {
    final id = r.product.id;
    _putHomeLikeOverride(id, r.product.isLiked ?? false);
    seedProductCardSocialCaches(
      id,
      likeCount: r.likeCount,
      reviewCount: r.reviewCount,
    );
    if (!mounted) return;
    setState(() {
      _mergeProductFromDetail(id, r.product, bumpResync: true);
    });
    // beklemeden: ortalama puan + review sayısı API ile tutarlı olsun (yarış azalır)
    unawaited(_refreshProductLikeStatus(id));
    unawaited(_loadFriendLikers());
  }

  void _mergeProductFromDetail(
    String productId,
    ProductDto updated, {
    bool bumpResync = false,
  }) {
    if (bumpResync) {
      _productCardResync[productId] = (_productCardResync[productId] ?? 0) + 1;
    }
    final fi = _filteredProducts.indexWhere((p) => p.id == productId);
    if (fi != -1) {
      _filteredProducts[fi] = updated;
    }
    for (final tab in HomeTopPicksTab.values) {
      final list = _topPicksByTab[tab]!;
      final i = list.indexWhere((p) => p.id == productId);
      if (i != -1) {
        final next = List<ProductDto>.from(list);
        next[i] = updated;
        _topPicksByTab[tab] = next;
      }
    }
    final si = _searchResults.indexWhere((p) => p.id == productId);
    if (si != -1) {
      _searchResults[si] = updated;
    }
  }

  void _onProductCardGridResync(String productId) {
    unawaited(_refreshProductLikeStatus(productId));
  }

  /// Sistem geri / gesture ile null dönüşte: sunucu gerçeği (cache revalidate, flash yok).
  Future<void> _refreshProductLikeStatus(String productId) async {
    final epochAtStart = _homeLikeMutationEpoch[productId] ?? 0;
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (token == null) return;

      final updatedProduct = await _productRepository.getProductById(
        productId,
        firebaseIdToken: token,
        bypassCache: true,
      );
      final likeCount = await _interactionRepository.getProductLikeCount(productId);
      final reviews = await _reviewRepository.getReviewsByProductId(
        productId,
        firebaseIdToken: token,
      );
      if (!mounted) return;
      final visible = filterVisibleReviews(reviews);
      final rc = visible.length;
      final sumRating = visible.fold<int>(0, (sum, r) => sum + r.rating);
      final computedRating = rc > 0 ? (sumRating / rc) : 0.0;
      if (!mounted) return;
      if ((_homeLikeMutationEpoch[productId] ?? 0) != epochAtStart) {
        return;
      }
      setProductCardSocialCaches(
        productId,
        likeCount: likeCount,
        reviewCount: rc,
        rating: computedRating,
        hasPhotoReview: anyVisibleReviewHasPhoto(visible),
      );
      _putHomeLikeOverride(productId, updatedProduct.isLiked ?? false);
      if (!mounted) return;
      setState(() {
        _mergeProductFromDetail(productId, updatedProduct, bumpResync: true);
      });
    } catch (_) {}
  }

  Future<void> _loadData({
    bool background = false,
    bool preserveLoadedProducts = false,
  }) async {
    final wasInCategoryMode =
        _activeCategoryPathPrefix != null && _selectedCategoryIndex != -1;
    final previousActivePrefix = _activeCategoryPathPrefix;
    final previousRootPath =
        (_selectedCategoryIndex >= 0 && _selectedCategoryIndex < _tags.length)
            ? _tags[_selectedCategoryIndex].categoryPath
            : null;
    if (!background) {
      _friendReviewSupplementCooldownUntil = null;
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      _errorMessage = null;
    }

    try {
      // Token opsiyonel: ürün listesi ve kategori artık token olmadan da 200 döner
      final firebaseIdToken = await _sessionHelper.ensureSession();

      List<TagDto> tags = [];
      try {
        tags = await _tagRepository.getRootTags(firebaseIdToken);
      } catch (_) {
        // Tags 401 verebilir; kategorileri boş bırak, ürünler yine yüklensin
      }

      if (!mounted) return;
      setState(() {
        _tags = tags;
        if (wasInCategoryMode && previousActivePrefix != null) {
          final restoredRootIndex = tags.indexWhere((t) {
            final path = t.categoryPath?.trim();
            if (path == null || path.isEmpty) return false;
            if (previousRootPath != null && previousRootPath == path) return true;
            return previousActivePrefix.startsWith(path);
          });
          if (restoredRootIndex != -1) {
            _selectedCategoryIndex = restoredRootIndex;
            _activeCategoryPathPrefix = previousActivePrefix;
            _isBannerCollapsed = true;
            _isLoadingSubTags = true;
            _subTags = [];
          } else {
            _activeCategoryPathPrefix = null;
            _selectedCategoryIndex = -1;
            _isBannerCollapsed = false;
          }
        } else {
          _activeCategoryPathPrefix = null;
          _selectedCategoryIndex = -1;
          _isBannerCollapsed = false;
        }
      });
      SearchWarmCache.instance.rememberRootTags(tags);
      if (wasInCategoryMode && _selectedCategoryIndex != -1) {
        final rootTag = _tags[_selectedCategoryIndex];
        unawaited(_loadSubTagsForRoot(rootTag));
      }
      await Future.wait([
        if (!(background && preserveLoadedProducts && _filteredProducts.isNotEmpty))
          _loadProductsPage(0),
        _loadFriendLikers(),
        if (!wasInCategoryMode) ...[
          _loadTopPicksForTab(HomeTopPicksTab.weeklyLikes),
          _loadTopPicksForTab(HomeTopPicksTab.forYou),
        ],
      ]);

      if (mounted) {
        setState(() {
          _isLoading = false;
          // Background refresh while restoring an already-rendered home feed should
          // not remount all cards; otherwise social meta rows briefly fall back to
          // loading placeholders on tab return.
          if (!(background && preserveLoadedProducts)) {
            _bumpProductCardCachesForListedProductIds();
          }
          final merged = FriendFeedMemoryCache.instance.peek()?.items;
          final source =
              (merged != null && merged.isNotEmpty)
                  ? merged
                  : _friendFeedItemsForLikers;
          var fresh = _buildFriendLikersMapForItems(source);
          var next = _mergeFriendLikersMapsPreserve(_friendLikersMap, fresh);
          next = _pruneFriendLikersMapByFollowing(next);
          _friendLikersMap = next;
        });
        unawaited(_persistFriendLikersMap());
        unawaited(_supplementFriendLikersFromFollowedReviews(force: !background));
      }
    } catch (e) {
      if (mounted) {
        if (background && _filteredProducts.isNotEmpty) {
          _isLoading = false;
          final merged = FriendFeedMemoryCache.instance.peek()?.items;
          final source =
              (merged != null && merged.isNotEmpty)
                  ? merged
                  : _friendFeedItemsForLikers;
          final fresh = _buildFriendLikersMapForItems(source);
          setState(() {
            var next = _mergeFriendLikersMapsPreserve(_friendLikersMap, fresh);
            next = _pruneFriendLikersMapByFollowing(next);
            _friendLikersMap = next;
          });
          unawaited(_persistFriendLikersMap());
          unawaited(_supplementFriendLikersFromFollowedReviews(force: false));
          return;
        }
        setState(() {
          _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _filteredProducts.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 70,
          automaticallyImplyLeading: false,
          leading: Center(
            child: SkeletonLoader(
              width: 36,
              height: 36,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          title: SkeletonLoader(
            width: 120,
            height: 28,
            borderRadius: BorderRadius.circular(8),
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SkeletonLoader(
                width: 36,
                height: 36,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ],
        ),
        body: CustomRefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: SkeletonLoader(
                    width: double.infinity,
                    height: 50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: SkeletonLoader(
                    width: 100,
                    height: 20,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                SizedBox(
                  height: 95,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: 6,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, __) => Column(
                      children: [
                        SkeletonLoader(
                          width: 62,
                          height: 62,
                          borderRadius: BorderRadius.circular(31),
                        ),
                        const SizedBox(height: 6),
                        SkeletonLoader(
                          width: 50,
                          height: 10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SkeletonLoader(
                    width: double.infinity,
                    height: 140,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSpacing.xLarge,
                          mainAxisSpacing: AppSpacing.xLarge,
                          childAspectRatio: 0.57,
                        ),
                    itemCount: 4,
                    itemBuilder: (_, __) => const ProductCardSkeleton(),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 70,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: Image.asset(
                  'assets/images/Chatbot.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            onPressed: () {},
          ),
          title: SizedBox(
            height: 90,
            width: 240,
            child: Image.asset(
              'assets/images/homepage_logo2.png',
              fit: BoxFit.contain,
            ),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppColors.error),
                const SizedBox(height: AppSpacing.large),
                Text(
                  _errorMessage ?? 'An error occurred',
                  style: AppTextStyles.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.large),
                ElevatedButton(
                  onPressed: _loadData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
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
        toolbarHeight: 70,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: Image.asset(
                'assets/images/Chatbot.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiChatPage()),
            );
          },
        ),
        title: SizedBox(
          height: 90,
          width: 240,
          child: Image.asset(
            'assets/images/homepage_logo2.png',
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: MessageUnreadService.instance.unreadCount,
                  builder: (context, unreadMsgCount, _) {
                    return Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline),
                          color: AppColors.primary,
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ConversationListPage(),
                              ),
                            );
                            // Geri dönünce anında sayıyı güncelle
                            unawaited(MessageUnreadService.instance.refreshNow());
                          },
                        ),
                        if (unreadMsgCount > 0)
                          Positioned(
                            right: 4,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                unreadMsgCount > 9
                                    ? '9+'
                                    : unreadMsgCount.toString(),
                                style: AppTextStyles.bodySecondary.copyWith(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: CustomRefreshIndicator(
        onRefresh: () async {
          await _loadData();
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SEARCH BAR
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _buildSearchBar(),
              ),
              const SizedBox(height: 20),

              // CATEGORIES
              _buildCategoriesSection(),

              // SUB-CATEGORIES
              _buildSubCategoryRow(),

              // BANNER — always visible when not searching, collapses when category is selected
              if (_searchQuery.isEmpty && _selectedCategoryIndex == -1) ...[
                const SizedBox(height: 14),
                _buildAnimatedBanner(),
              ],

              // SORT BAR
              if (_searchQuery.isEmpty) ...[
                const SizedBox(height: 12),
                _buildSortBar(),
              ],

              // PRODUCT GRID
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: _buildProductGrid(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        offset: _showScrollToTop ? Offset.zero : const Offset(0, 1.4),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _showScrollToTop ? 1 : 0,
          child: FloatingActionButton.small(
            heroTag: 'home_scroll_to_top',
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 3,
            onPressed: _scrollToTop,
            child: const Icon(Icons.keyboard_arrow_up_rounded, size: 22),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}


// ─── Sub-category chip (styled to match parent category color) ───────────────

class _SubChip extends StatelessWidget {
  final String title;
  final bool selected;
  final Color iconColor;
  final VoidCallback? onTap;

  const _SubChip({
    required this.title,
    required this.iconColor,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayTitle = _formatCategoryLabel(title);
    final textColor = selected ? AppColors.textPrimary : AppColors.textSecondary;
    final underlineColor = selected
        ? AppColors.primary.withValues(alpha: 0.9)
        : AppColors.textSecondary.withValues(alpha: 0.35);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          displayTitle,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.1,
            decoration: TextDecoration.underline,
            decorationColor: underlineColor,
            decorationThickness: selected ? 2.2 : 1.0,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// ─── Horizontal kategori scroll kartı ────────────────────────────────────────

/// Birleşik kategori adlarını okunur hale getirir.
/// Örn: `BeautyandPersonalCare` -> `Beauty and Personal Care`
String _formatCategoryLabel(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return raw;

  // Snake / kebab adlarını normalize et.
  text = text.replaceAll('_', ' ').replaceAll('-', ' ');
  // `BeautyandPersonalCare` gibi kalıpta "and" bağlacını ayır.
  text = text.replaceAllMapped(
    RegExp(r'([a-z])and([A-Z])'),
    (m) => '${m.group(1)} and ${m.group(2)}',
  );
  // Camel/Pascal case ayır.
  text = text.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  // Fazla boşlukları sadeleştir.
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Ana sayfa yatay kategori: güzellik + kişisel bakım birleşik etiketi kısa gösterilir.
  final lower = text.toLowerCase();
  if (lower.contains('beauty') && lower.contains('personal')) {
    return 'Beauty';
  }

  return text;
}

/// Kategori adına göre (icon, iconColor, bgColor) döndürür
({IconData icon, Color iconColor, Color bgColor}) _categoryStyle(String name) {
  // Normalize: lowercase and remove spaces so CamelCase also matches
  final n = name.toLowerCase();
  final nc = n.replaceAll(' ', '').replaceAll('&', '').replaceAll('-', '');

  bool has(String kw) => n.contains(kw) || nc.contains(kw);

  // ── Clothing & Fashion ───────────────────────────────────────────────────
  if (has('giyim') || has('moda') || has('tekstil') || has('kıyafet') ||
      has('elbise') || has('tişört') || has('gömlek') || has('pantolon') ||
      has('ceket') || has('mont') || has('kaban') || has('kazak') ||
      has('clothing') || has('fashion') || has('apparel') || has('wear') ||
      has('outfit') || has('dress') || has('shirt') || has('jacket') ||
      has('coat') || has('sweater') || has('jeans') || has('trousers')) {
    return (icon: Icons.checkroom_outlined, iconColor: const Color(0xFF8E24AA), bgColor: const Color(0xFFF3E5F5));
  }

  // ── Footwear ─────────────────────────────────────────────────────────────
  if (has('ayakkabı') || has('bot') || has('sandalet') || has('terlik') ||
      has('çizme') || has('sneaker') || has('shoes') || has('footwear') ||
      has('boots') || has('sandals') || has('slippers')) {
    return (icon: Icons.run_circle_outlined, iconColor: const Color(0xFF6A1B9A), bgColor: const Color(0xFFEDE7F6));
  }

  // ── Electronics & Computers ──────────────────────────────────────────────
  if (has('elektronik') || has('teknoloji') || has('bilgisayar') ||
      has('laptop') || has('tablet') || has('monitor') || has('monitör') ||
      has('computer') || has('electronics') || has('technology') ||
      has('pc') || has('notebook') || has('printer') || has('yazıcı')) {
    return (icon: Icons.computer_outlined, iconColor: const Color(0xFF1565C0), bgColor: const Color(0xFFE3F2FD));
  }

  // ── Phone & Mobile Accessories ───────────────────────────────────────────
  if (has('telefon') || has('akıllı') || has('cep') || has('kulaklık') ||
      has('hoparlör') || has('şarj') || has('bluetooth') || has('powerbank') ||
      has('phone') || has('mobile') || has('smartphone') || has('headphone') ||
      has('earphone') || has('charger') || has('speaker') || has('cable')) {
    return (icon: Icons.phone_android_outlined, iconColor: const Color(0xFF1976D2), bgColor: const Color(0xFFE3F2FD));
  }

  // ── TV & Large Appliances ────────────────────────────────────────────────
  if (has('televizyon') || has('klima') || has('çamaşır') || has('bulaşık') ||
      has('television') || has('aircon') || has('washing') || has('dishwasher') ||
      has('refrigerator') || has('buzdolabı') || n == 'tv' || nc == 'tv') {
    return (icon: Icons.tv_outlined, iconColor: const Color(0xFF0277BD), bgColor: const Color(0xFFE1F5FE));
  }

  // ── Kitchen & Small Appliances ───────────────────────────────────────────
  if (has('mutfak') || has('beyaz eşya') || has('ankastre') || has('blender') ||
      has('tost') || has('kitchen') || has('appliance') || has('cookware') ||
      has('microwave') || has('fırın') || has('oven') || has('coffeemaker')) {
    return (icon: Icons.kitchen_outlined, iconColor: const Color(0xFF00838F), bgColor: const Color(0xFFE0F7FA));
  }

  // ── Furniture & Home Décor ────────────────────────────────────────────────
  if (has('mobilya') || has('dekorasyon') || has('halı') || has('perde') ||
      has('koltuk') || has('dolap') || has('yatak') || has('furniture') ||
      has('decor') || has('decoration') || has('rug') || has('curtain') ||
      has('sofa') || has('wardrobe') || has('bed') || has('mattress')) {
    return (icon: Icons.chair_outlined, iconColor: const Color(0xFF2E7D32), bgColor: const Color(0xFFE8F5E9));
  }

  // ── Home & Living (generic) ──────────────────────────────────────────────
  if (has('yaşam') || has('house') || has('homedecor') || has('homefurnishing') ||
      n == 'home' || n == 'ev' || n.startsWith('ev ') || n.startsWith('home ')) {
    return (icon: Icons.home_outlined, iconColor: const Color(0xFF388E3C), bgColor: const Color(0xFFE8F5E9));
  }

  // ── Beauty & Personal Care ────────────────────────────────────────────────
  if (has('kozmetik') || has('güzellik') || has('parfüm') || has('makyaj') ||
      has('cilt') || has('şampuan') || has('kişisel bakım') || has('bakım') ||
      has('beauty') || has('cosmetic') || has('makeup') || has('skincare') ||
      has('haircare') || has('perfume') || has('personalcare') ||
      has('personal care') || has('fragrance') || has('lotion') || has('cream')) {
    return (icon: Icons.face_retouching_natural_outlined, iconColor: const Color(0xFFAD1457), bgColor: const Color(0xFFFCE4EC));
  }

  // ── Sports & Outdoors ────────────────────────────────────────────────────
  if (has('spor') || has('outdoor') || has('fitness') || has('koşu') ||
      has('bisiklet') || has('yoga') || has('futbol') || has('basketbol') ||
      has('sport') || has('running') || has('cycling') || has('football') ||
      has('basketball') || has('tennis') || has('golf') || has('swim') ||
      has('gym') || has('exercise') || has('athletic')) {
    return (icon: Icons.fitness_center_outlined, iconColor: const Color(0xFFE65100), bgColor: const Color(0xFFFFF3E0));
  }

  // ── Hobbies & Crafts ─────────────────────────────────────────────────────
  if (has('hobi') || has('el işi') || has('çizim') || has('resim') ||
      has('hobby') || has('hobbies') || has('craft') || has('art') ||
      has('drawing') || has('painting') || has('diy') || has('model')) {
    return (icon: Icons.palette_outlined, iconColor: const Color(0xFF7B1FA2), bgColor: const Color(0xFFF3E5F5));
  }

  // ── Books & Stationery ───────────────────────────────────────────────────
  if (has('kitap') || has('kırtasiye') || has('ofis') || has('defter') ||
      has('roman') || has('ders') || has('book') || has('stationery') ||
      has('office') || has('magazine') || has('novel') || has('literature') ||
      has('education') || has('pen') || has('notebook')) {
    return (icon: Icons.menu_book_outlined, iconColor: const Color(0xFF4527A0), bgColor: const Color(0xFFEDE7F6));
  }

  // ── Toys & Baby ──────────────────────────────────────────────────────────
  if (has('oyuncak') || has('lego') || has('puzzle') || has('peluş') ||
      has('bebek') || has('çocuk') || has('anne') || has('hamile') ||
      has('toy') || has('toys') || has('baby') || has('kids') || has('child') ||
      has('children') || has('infant') || has('maternity') || has('toddler')) {
    return (icon: Icons.toys_outlined, iconColor: const Color(0xFFC62828), bgColor: const Color(0xFFFFEBEE));
  }

  // ── Supermarket & Food ───────────────────────────────────────────────────
  if (has('market') || has('süpermarket') || has('gıda') || has('içecek') ||
      has('meyve') || has('sebze') || has('bakliyat') || has('çikolata') ||
      has('grocery') || has('food') || has('supermarket') || has('beverage') ||
      has('drink') || has('snack') || has('organic') || has('fresh')) {
    return (icon: Icons.shopping_basket_outlined, iconColor: const Color(0xFF558B2F), bgColor: const Color(0xFFF1F8E9));
  }

  // ── Automotive ───────────────────────────────────────────────────────────
  if (has('otomotiv') || has('araba') || has('araç') || has('lastik') ||
      has('automotive') || has('car') || has('vehicle') || has('tire') ||
      has('auto') || has('motorcycle') || has('motor') || has('spare part')) {
    return (icon: Icons.directions_car_outlined, iconColor: const Color(0xFF37474F), bgColor: const Color(0xFFECEFF1));
  }

  // ── Garden & Plants ──────────────────────────────────────────────────────
  if (has('bahçe') || has('çiçek') || has('bitki') || has('tohum') ||
      has('garden') || has('plant') || has('flower') || has('seed') ||
      has('outdoor plant') || has('gardening') || has('pot')) {
    return (icon: Icons.yard_outlined, iconColor: const Color(0xFF33691E), bgColor: const Color(0xFFF9FBE7));
  }

  // ── Pet & Animals ────────────────────────────────────────────────────────
  if (has('evcil') || has('hayvan') || has('kedi') || has('köpek') ||
      has('pet') || has('animal') || has('cat') || has('dog') ||
      has('bird') || has('fish') || has('aquarium') || has('paw')) {
    return (icon: Icons.pets_outlined, iconColor: const Color(0xFF6D4C41), bgColor: const Color(0xFFEFEBE9));
  }

  // ── Health & Medical ─────────────────────────────────────────────────────
  if (has('sağlık') || has('medikal') || has('eczane') || has('vitamin') ||
      has('diş') || has('ilaç') || has('health') || has('medical') ||
      has('pharmacy') || has('vitamin') || has('supplement') || has('dental') ||
      has('wellness') || has('medicine') || has('drug') || has('bandage')) {
    return (icon: Icons.health_and_safety_outlined, iconColor: const Color(0xFF00695C), bgColor: const Color(0xFFE0F2F1));
  }

  // ── Tableware ─────────────────────────────────────────────────────────────
  if (has('züccaciye') || has('sofra') || has('çatal') || has('tencere') ||
      has('tableware') || has('cutlery') || has('cookware') || has('plate') ||
      has('bowl') || has('cup') || has('glass') || has('pot') || has('pan')) {
    return (icon: Icons.restaurant_outlined, iconColor: const Color(0xFFBF360C), bgColor: const Color(0xFFFBE9E7));
  }

  // ── Camping & Nature ─────────────────────────────────────────────────────
  if (has('kamp') || has('doğa') || has('trekking') || has('çadır') ||
      has('camping') || has('nature') || has('tent') || has('hiking') ||
      has('trail') || has('backpack') || has('sleeping bag')) {
    return (icon: Icons.forest_outlined, iconColor: const Color(0xFF1B5E20), bgColor: const Color(0xFFE8F5E9));
  }

  // ── Accessories & Jewelry ────────────────────────────────────────────────
  if (has('aksesuar') || has('takı') || has('mücevher') || has('yüzük') ||
      has('kolye') || has('küpe') || has('bilezik') || has('kemer') ||
      has('accessory') || has('accessories') || has('jewelry') || has('jewellery') ||
      has('necklace') || has('ring') || has('earring') || has('bracelet') ||
      has('belt') || has('hat') || has('scarf') || has('sunglasses')) {
    return (icon: Icons.diamond_outlined, iconColor: const Color(0xFF6A1B9A), bgColor: const Color(0xFFF3E5F5));
  }

  // ── Watches ──────────────────────────────────────────────────────────────
  if (has('saat') || has('watch') || has('smartwatch') || has('clock')) {
    return (icon: Icons.watch_outlined, iconColor: const Color(0xFF4E342E), bgColor: const Color(0xFFEFEBE9));
  }

  // ── Bags & Luggage ───────────────────────────────────────────────────────
  if (has('çanta') || has('valiz') || has('bavul') || has('bag') ||
      has('luggage') || has('suitcase') || has('backpack') || has('purse') ||
      has('handbag') || has('wallet')) {
    return (icon: Icons.luggage_outlined, iconColor: const Color(0xFF4E342E), bgColor: const Color(0xFFEFEBE9));
  }

  // ── Construction & DIY ───────────────────────────────────────────────────
  if (has('yapı') || has('tadilat') || has('hırdavat') || has('alet') ||
      has('construction') || has('hardware') || has('tool') || has('diy') ||
      has('building') || has('paint') || has('drill') || has('renovation')) {
    return (icon: Icons.construction_outlined, iconColor: const Color(0xFF37474F), bgColor: const Color(0xFFECEFF1));
  }

  // ── Gaming & Consoles ────────────────────────────────────────────────────
  if (has('oyun') || has('konsol') || has('gaming') || has('playstation') ||
      has('game') || has('console') || has('xbox') || has('nintendo') ||
      has('videogame') || has('esports') || has('gamer')) {
    return (icon: Icons.sports_esports_outlined, iconColor: const Color(0xFF283593), bgColor: const Color(0xFFE8EAF6));
  }

  // ── Photo & Camera ───────────────────────────────────────────────────────
  if (has('fotoğraf') || has('kamera') || has('optik') || has('lens') ||
      has('photo') || has('camera') || has('photography') || has('optic') ||
      has('video camera') || has('drone')) {
    return (icon: Icons.camera_alt_outlined, iconColor: const Color(0xFF37474F), bgColor: const Color(0xFFECEFF1));
  }

  // ── Music & Instruments ──────────────────────────────────────────────────
  if (has('müzik') || has('enstrüman') || has('gitar') || has('piyano') ||
      has('music') || has('instrument') || has('guitar') || has('piano') ||
      has('drum') || has('violin') || has('audio') || has('sound system')) {
    return (icon: Icons.music_note_outlined, iconColor: const Color(0xFFAD1457), bgColor: const Color(0xFFFCE4EC));
  }

  // ── Film & Entertainment ─────────────────────────────────────────────────
  if (has('film') || has('sinema') || has('dizi') || has('movie') ||
      has('cinema') || has('dvd') || has('entertainment') || has('series')) {
    return (icon: Icons.movie_outlined, iconColor: const Color(0xFF283593), bgColor: const Color(0xFFE8EAF6));
  }

  // ── Lighting ─────────────────────────────────────────────────────────────
  if (has('aydınlatma') || has('lamba') || has('avize') || has('lighting') ||
      has('lamp') || has('led') || has('chandelier') || has('bulb') ||
      has('lantern') || has('nightlight')) {
    return (icon: Icons.lightbulb_outlined, iconColor: const Color(0xFFF57F17), bgColor: const Color(0xFFFFF8E1));
  }

  // ── Textile & Bedding ─────────────────────────────────────────────────────
  if (has('yastık') || has('yorgan') || has('nevresim') || has('havlu') ||
      has('bedding') || has('pillow') || has('quilt') || has('towel') ||
      has('duvet') || has('blanket') || has('linen') || has('textile')) {
    return (icon: Icons.bed_outlined, iconColor: const Color(0xFF0277BD), bgColor: const Color(0xFFE1F5FE));
  }

  // Fallback: derive a unique icon+color from the name's characters
  final fallbacks = [
    (icon: Icons.shopping_bag_outlined, iconColor: const Color(0xFF1976D2), bgColor: const Color(0xFFE3F2FD)),
    (icon: Icons.star_border_rounded, iconColor: const Color(0xFF6A1B9A), bgColor: const Color(0xFFF3E5F5)),
    (icon: Icons.local_offer_outlined, iconColor: const Color(0xFFBF360C), bgColor: const Color(0xFFFBE9E7)),
    (icon: Icons.storefront_outlined, iconColor: const Color(0xFF00695C), bgColor: const Color(0xFFE0F2F1)),
    (icon: Icons.category_outlined, iconColor: const Color(0xFF37474F), bgColor: const Color(0xFFECEFF1)),
    (icon: Icons.inventory_2_outlined, iconColor: const Color(0xFF4527A0), bgColor: const Color(0xFFEDE7F6)),
    (icon: Icons.redeem_outlined, iconColor: const Color(0xFF558B2F), bgColor: const Color(0xFFF1F8E9)),
  ];
  final idx = (nc.codeUnitAt(0) + nc.length) % fallbacks.length;
  return fallbacks[idx];
}

class _CircleCategoryItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const _CircleCategoryItem({
    required this.label,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = _categoryStyle(label);
    final displayLabel = _formatCategoryLabel(label);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? style.bgColor : style.bgColor.withValues(alpha: 0.55),
                border: isSelected
                    ? Border.all(color: style.iconColor, width: 2.5)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? style.iconColor.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.06),
                    blurRadius: isSelected ? 8 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  style.icon,
                  size: 26,
                  color: isSelected
                      ? style.iconColor
                      : style.iconColor.withValues(alpha: 0.65),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              displayLabel,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? style.iconColor : AppColors.textPrimary,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Banner Carousel ──────────────────────────────────────────────────────────

class _BannerCarousel extends StatefulWidget {
  final void Function(HomeTopPicksTab) onBannerTap;

  const _BannerCarousel({
    super.key,
    required this.onBannerTap,
  });

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _currentPage = 0;

  static const _banners = [
    (
      tab: HomeTopPicksTab.weeklyLikes,
      title: 'Most Liked',
      subtitle: 'Explore the most liked products this week',
      icon: Icons.local_fire_department_rounded,
      gradientEnd: Color(0xFFFF4081),
    ),
    (
      tab: HomeTopPicksTab.forYou,
      title: 'For You',
      subtitle: 'Personalized picks based on your taste',
      icon: Icons.stars_rounded,
      gradientEnd: Color(0xFF7C4DFF),
    ),
  ];

  void _startAutoScroll() {
    _timer?.cancel();
    _timer = Timer.periodic(AppBackgroundTimers.homePromoBannerStep, (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % _banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _controller,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, i) {
              final b = _banners[i];
              return GestureDetector(
                onTap: () {
                  _timer?.cancel();
                  widget.onBannerTap(b.tab);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, b.gradientEnd],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -20,
                          top: -20,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 30,
                          bottom: -30,
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 110, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                b.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                b.subtitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Tap to explore',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 20,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                              child: Icon(b.icon, color: Colors.white, size: 34),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_banners.length, (i) {
            final active = _currentPage == i;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: active ? 20 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}


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
import '../../../core/routes/custom_page_transitions.dart';
import '../../../core/utils/in_flight_id_lock.dart';
import '../../../core/cache/following_id_set_cache.dart';
import '../../../core/cache/home_feed_cache.dart';
import '../../../core/cache/home_top_picks_cache.dart';
import '../../../core/config/app_background_timers.dart';
import '../../../core/cache/search_warm_cache.dart';
import '../../../core/cache/friend_feed_memory_cache.dart';
import '../../../features/activity/domain/activity_models.dart';
import '../../../features/activity/domain/activity_type.dart';
import '../../../features/activity/data/friends_feed_repository.dart';
import '../../../features/activity/data/friends_feed_activity_mapper.dart';
import '../widgets/product_card.dart';
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
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
  bool _isLoading = true;
  bool _isFiltering = false;
  bool _isLoadingMore = false; // Infinite scroll: sonraki sayfa yüklenirken
  bool _isLoadingSubTags = false;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();
  bool _notificationSvcAttached = false;

  // --- Friend likers: yalnızca son friends-feed API cevabı; önbirleşik cache’deki eski satırlar kullanılmaz ---
  List<ActivityItem> _friendFeedItemsForLikers = const [];
  Map<String, List<String>> _friendLikersMap = {};

  /// [ProductCard] key parçası — ürün detayından dönünce like sayısı tazelensin.
  final Map<String, int> _productCardResync = {};
  final InFlightIdLock _homeProductLikeLock = InFlightIdLock();

  // --- Banner collapse state ---
  bool _isBannerCollapsed = false;

  // --- Inline search (aynı katalog: Search ekranı gibi tüm ürünler) ---
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<ProductDto> _searchResults = [];
  Timer? _searchDebounce;
  /// Tüm kategori ana sayfasında: yeni ürünler için arka planda periyodik kontrol.
  Timer? _homeFeedPollTimer;
  bool _homeFeedPollInFlight = false;
  /// Her N ana sayfa poll’unda arkadaş feed’i yenile (like → avatar haritası güncellensin).
  int _friendFeedRefreshPollTick = 0;
  int _searchReqSeq = 0;
  bool _isSearchLoading = false;

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
          Navigator.pushReplacement(
            context,
            _noAnimationRoute(const SearchPage()),
          );
          return;
        }
        if (index == 1) {
          Navigator.pushReplacement(
            context,
            _noAnimationRoute(const FriendFeedPage()),
          );
          return;
        }
        if (index == 2) {
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
    );
  }

  @override
  void initState() {
    super.initState();
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
    if (homeSnap != null && homeSnap.content.isNotEmpty) {
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
    unawaited(_loadFriendLikers());
    unawaited(_warmSearchCatalogInBackground());
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


  /// Loads friend feed from backend, populates the memory cache and
  /// immediately rebuilds [_friendLikersMap] so avatars show on first open.
  Future<void> _loadFriendLikers() async {
    try {
      final page = await _friendsFeedRepository.getFriendsFeed(
        page: 0,
        size: 50,
      );
      if (!mounted) return;

      final items = activityItemsFromFriendsFeedDtos(page.content);
      _friendFeedItemsForLikers = items;

      // Merge with existing cache: friend feed ekranı için — ana sayfa baloncuğu buna bakmaz.
      final existing = FriendFeedMemoryCache.instance.peek();
      final merged = <String, dynamic>{};
      for (final item in [...items, ...?existing?.items]) {
        merged.putIfAbsent(item.id, () => item);
      }
      FriendFeedMemoryCache.instance.remember(
        items: merged.values.cast<dynamic>().toList().cast(),
        page: page.number,
        totalPages: page.totalPages,
      );

      if (mounted) {
        setState(() {
          _friendLikersMap = _buildFriendLikersMapForItems(items);
        });
      }
    } catch (_) {
      // Friend likers are optional — silent fail.
      if (mounted && _friendLikersMap.isEmpty) {
        setState(() {
          _friendLikersMap = _buildFriendLikersMapForItems(_friendFeedItemsForLikers);
        });
      }
    }
  }

  /// Ürün kartı baloncuğu: sadece [source] satırları. Askı/deaktif aktör yok, eski cache yok.
  Map<String, List<String>> _buildFriendLikersMapForItems(
    Iterable<ActivityItem> source,
  ) {
    final map = <String, List<String>>{};
    for (final item in source) {
      if (item.isActorInactive) continue;
      // Baloncuklar yalnızca gerçekten review bırakan kullanıcıları göstersin.
      if (item.type != ActivityType.review) {
        continue;
      }
      final productId = item.targetContent?.productId;
      final avatarUrl = item.user.avatarUrl;
      if (productId == null || productId.isEmpty) continue;
      if (avatarUrl == null || avatarUrl.trim().isEmpty) continue;
      map.putIfAbsent(productId, () => []);
      if (!map[productId]!.contains(avatarUrl)) {
        map[productId]!.add(avatarUrl);
      }
    }
    return map;
  }

  /// Search sayfasıyla aynı: GET /api/products tüm ürün listesi (önbellek + arka planda ısıtma).
  Future<void> _warmSearchCatalogInBackground() async {
    if (SearchWarmCache.instance.peekSeedProducts().isNotEmpty) return;
    try {
      final products = await _productRepository.getAllProductsRaw();
      if (products.isNotEmpty) {
        SearchWarmCache.instance.rememberSeedProducts(products);
      }
    } catch (_) {}
  }

  Future<List<ProductDto>> _ensureSearchCatalog() async {
    var pool = SearchWarmCache.instance.peekSeedProducts();
    if (pool.isNotEmpty) return pool;
    final products = await _productRepository.getAllProductsRaw();
    if (products.isNotEmpty) {
      SearchWarmCache.instance.rememberSeedProducts(products);
    }
    return products;
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
      HomeTopPicksCache.remember(tab, products);
      setState(() => _topPicksByTab[tab] = products);
    } catch (_) {
      // silently fail
    } finally {
      _topPicksLoadingTabs.remove(tab);
      if (mounted) setState(() {});
    }
  }

  /// Infinite scroll: listenere yaklaşınca sonraki sayfayı yükle
  void _onScroll() {
    if (_isFiltering || _isLoadingMore || _filteredProducts.isEmpty) return;
    if (_currentPage + 1 >= _totalPages) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMoreProducts();
    }
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
      );
      if (!mounted) return;

      if (_homeFeedFirstPageUnchanged(result)) return;

      // Aşağıdayken yeni ürün gelse bile listenin başı zıplamasın
      final savedOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;
      const keepScrollThreshold = 32.0;

      setState(() {
        _filteredProducts = result.content;
        _currentPage = result.number;
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
        );
      } else {
        result = await _productRepository.getHomeFeed(
          page: page,
          size: 10,
          firebaseIdToken: firebaseIdToken,
        );
      }

      if (!mounted) return;

      setState(() {
        if (append && page > 0) {
          _filteredProducts = [..._filteredProducts, ...result.content];
        } else {
          _filteredProducts = result.content;
        }
        _currentPage = result.number;
        _totalPages = result.totalPages;
        _totalElements = result.totalElements;
        _isFiltering = false;
      });

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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFiltering = false;
        _filteredProducts = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load products: ${ErrorHandler.getUserFriendlyMessage(e)}',
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
            child: Text('No products found', style: AppTextStyles.bodySecondary),
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
            isFavorite: product.isLiked ?? false,
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
              final messenger = ScaffoldMessenger.of(context);
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Please login to like products'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              if (!_homeProductLikeLock.tryEnter(product.id)) return;
              try {
                final tabProducts = _topPicksByTab[tab]!;
                final idx = tabProducts.indexWhere((p) => p.id == product.id);
                final bool beforeLike =
                    idx != -1 ? (tabProducts[idx].isLiked ?? false) : (product.isLiked ?? false);
                if (idx != -1) {
                  applyLocalLikeCountDeltaOnToggle(
                    product.id,
                    wasLiked: beforeLike,
                    isNowLiked: !beforeLike,
                  );
                  setState(() {
                    _topPicksByTab[tab]![idx] =
                        tabProducts[idx].copyWith(isLiked: !beforeLike);
                  });
                }
                try {
                  final token = await _sessionHelper.getTokenAndSetHeader();
                  if (token == null) {
                    throw Exception('Failed to get Firebase ID token');
                  }
                  final newLikeStatus =
                      await _interactionRepository.toggleProductLike(token, product.id);
                  if (newLikeStatus != !beforeLike) {
                    applyLocalLikeCountDeltaOnToggle(
                      product.id,
                      wasLiked: !beforeLike,
                      isNowLiked: newLikeStatus,
                    );
                  }
                  if (idx != -1) {
                    setState(() {
                      _topPicksByTab[tab]![idx] =
                          _topPicksByTab[tab]![idx].copyWith(isLiked: newLikeStatus);
                    });
                  }
                } catch (e) {
                  if (idx != -1) {
                    applyLocalLikeCountDeltaOnToggle(
                      product.id,
                      wasLiked: !beforeLike,
                      isNowLiked: beforeLike,
                    );
                    setState(() {
                      _topPicksByTab[tab]![idx] =
                          _topPicksByTab[tab]![idx].copyWith(isLiked: beforeLike);
                    });
                  }
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(ErrorHandler.getUserFriendlyMessage(e)),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              } finally {
                _homeProductLikeLock.leave(product.id);
              }
            },
          );
        },
      );
    }

    // ── Inline search results (Search ekranıyla aynı katalog + yüklenme) ──
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
            isFavorite: product.isLiked ?? false,
            loadReviewCount: false,
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
            onFavoriteTap: () {},
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
              isFavorite: product.isLiked ?? false,
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
                final messenger = ScaffoldMessenger.of(context);
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Please login to like products'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }
                if (!_homeProductLikeLock.tryEnter(product.id)) return;
                try {
                  final filteredIndex =
                      _filteredProducts.indexWhere((p) => p.id == product.id);
                  final bool beforeLike = filteredIndex != -1
                      ? (_filteredProducts[filteredIndex].isLiked ?? false)
                      : (product.isLiked ?? false);
                  if (filteredIndex != -1) {
                    applyLocalLikeCountDeltaOnToggle(
                      product.id,
                      wasLiked: beforeLike,
                      isNowLiked: !beforeLike,
                    );
                    setState(() {
                      _filteredProducts[filteredIndex] =
                          _filteredProducts[filteredIndex]
                              .copyWith(isLiked: !beforeLike);
                    });
                  }
                  try {
                    final token = await _sessionHelper.getTokenAndSetHeader();
                    if (token == null) {
                      throw Exception('Failed to get Firebase ID token');
                    }
                    final newLikeStatus = await _interactionRepository
                        .toggleProductLike(token, product.id);
                    if (newLikeStatus != !beforeLike) {
                      applyLocalLikeCountDeltaOnToggle(
                        product.id,
                        wasLiked: !beforeLike,
                        isNowLiked: newLikeStatus,
                      );
                    }
                    if (filteredIndex != -1) {
                      setState(() {
                        _filteredProducts[filteredIndex] =
                            _filteredProducts[filteredIndex]
                                .copyWith(isLiked: newLikeStatus);
                      });
                    }
                  } catch (e) {
                    if (filteredIndex != -1) {
                      applyLocalLikeCountDeltaOnToggle(
                        product.id,
                        wasLiked: !beforeLike,
                        isNowLiked: beforeLike,
                      );
                      setState(() {
                        _filteredProducts[filteredIndex] =
                            _filteredProducts[filteredIndex]
                                .copyWith(isLiked: beforeLike);
                      });
                    }
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(ErrorHandler.getUserFriendlyMessage(e)),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  }
                } finally {
                  _homeProductLikeLock.leave(product.id);
                }
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

  /// [ReviewPage] dönüşünde grid, sayı ve favori durumu anında (flash’sız) güncellenir.
  void _applyProductFromReviewExit(ReviewPagePopResult r) {
    final id = r.product.id;
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

  /// Sistem geri / gesture ile null dönüşte: sunucu gerçeği (cache revalidate, flash yok).
  Future<void> _refreshProductLikeStatus(String productId) async {
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
      setProductCardSocialCaches(
        productId,
        likeCount: likeCount,
        reviewCount: filterVisibleReviews(reviews).length,
      );
      if (!mounted) return;
      setState(() {
        _mergeProductFromDetail(productId, updatedProduct, bumpResync: true);
      });
    } catch (_) {}
  }

  Future<void> _loadData({bool background = false}) async {
    final wasInCategoryMode =
        _activeCategoryPathPrefix != null && _selectedCategoryIndex != -1;
    final previousActivePrefix = _activeCategoryPathPrefix;
    final previousRootPath =
        (_selectedCategoryIndex >= 0 && _selectedCategoryIndex < _tags.length)
            ? _tags[_selectedCategoryIndex].categoryPath
            : null;
    if (!background) {
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
        _loadProductsPage(0),
        if (!wasInCategoryMode) ...[
          _loadTopPicksForTab(HomeTopPicksTab.weeklyLikes),
          _loadTopPicksForTab(HomeTopPicksTab.forYou),
        ],
      ]);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _friendLikersMap = _buildFriendLikersMapForItems(_friendFeedItemsForLikers);
        });
      }
    } catch (e) {
      if (mounted) {
        if (background && _filteredProducts.isNotEmpty) {
          _isLoading = false;
          _friendLikersMap =
              _buildFriendLikersMapForItems(_friendFeedItemsForLikers);
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

              // PRODUCT GRID
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: _buildProductGrid(),
              ),
            ],
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? iconColor : iconColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? iconColor : iconColor.withValues(alpha: 0.3),
            width: 1.1,
          ),
        ),
        child: Text(
          displayTitle,
          style: TextStyle(
            color: selected ? Colors.white : iconColor,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.1,
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


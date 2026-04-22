import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_chip_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/session_helper.dart';
import '../../../core/notifications/notification_realtime_service.dart';
import '../../../core/widgets/main_bottom_nav_items.dart';
import '../../../features/activity/presentation/activity_page.dart';
import '../../../core/widgets/custom_refresh_indicator.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/routes/custom_page_transitions.dart';
import '../../../core/cache/search_warm_cache.dart';
import '../widgets/product_card.dart';
import '../widgets/top_product_card.dart';
import 'messages/conversation_list_page.dart';
import 'messages/ai_chat_page.dart';
import '../data/repositories/message_repository.dart';
import 'search_page.dart';
import 'friend_feed_page.dart';
import 'profile/pages/profile_page.dart';
import 'review/pages/review_page.dart';
import '../data/repositories/tag_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/interaction_repository.dart';
import '../data/services/review_prefetch_service.dart';
import '../data/models/tag_dto.dart';
import '../data/models/product_dto.dart';
import '../data/models/product_search_result_dto.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _TopPicksTab { trendingReviews, weeklyLikes, forYou }

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  // BottomNavigationBar index mapping:
  // 0: search, 1: add (placeholder), 2: home, 3: activity, 4: profile
  int _selectedCategoryIndex = -1; // -1 means "All", 0+ means selected category
  int _selectedSubCategoryIndex = -1; // -1 means none
  final TagRepository _tagRepository = TagRepository();
  final ProductRepository _productRepository = ProductRepository();
  final InteractionRepository _interactionRepository = InteractionRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final MessageRepository _messageRepository = MessageRepository();

  List<TagDto> _tags = [];
  List<TagDto> _subTags = [];
  // Statik bellek cache — sayfa yeniden açıldığında anında göster
  static final Map<_TopPicksTab, List<ProductDto>> _topPicksStaticCache = {};

  final Map<_TopPicksTab, List<ProductDto>> _topPicksByTab = {
    _TopPicksTab.trendingReviews: [],
    _TopPicksTab.weeklyLikes: [],
    _TopPicksTab.forYou: [],
  };
  final Map<_TopPicksTab, String?> _topPicksErrorByTab = {
    _TopPicksTab.trendingReviews: null,
    _TopPicksTab.weeklyLikes: null,
    _TopPicksTab.forYou: null,
  };
  final Set<_TopPicksTab> _topPicksLoadingTabs = <_TopPicksTab>{};
  final Map<_TopPicksTab, int> _topPicksLatestRequestByTab = {};
  int _topPicksRequestSeq = 0;
  late final TabController _topPicksTabController;
  final ScrollController _topPicksScrollController = ScrollController();
  _TopPicksTab _selectedTopPicksTab = _TopPicksTab.trendingReviews;
  bool _isTopPicksLoading = true; // başlangıçta skeleton göster
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
  int _unreadMessageCount = 0;
  bool _notificationSvcAttached = false;
  Timer? _unreadBadgeTimer;

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
    _topPicksTabController = TabController(
      length: _TopPicksTab.values.length,
      vsync: this,
      initialIndex: 0,
    )..addListener(_onTopPicksTabControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hookNotificationsIfSignedIn());
    });
    // Top picks statik cache'den yükle → anında göster
    for (final tab in _TopPicksTab.values) {
      final cached = _topPicksStaticCache[tab];
      if (cached != null && cached.isNotEmpty) {
        _topPicksByTab[tab] = List<ProductDto>.from(cached);
      }
    }
    if (_topPicksByTab[_selectedTopPicksTab]?.isNotEmpty == true) {
      _isTopPicksLoading = false;
    }
    final warmTags = SearchWarmCache.instance.peekRootTags();
    final warmProducts = SearchWarmCache.instance.peekSeedProducts();
    if (warmTags.isNotEmpty || warmProducts.isNotEmpty) {
      _tags = warmTags;
      // warmProducts home feed'den gelir — trending olarak gösterme
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
    _loadUnreadCount();
    // Her 30 saniyede badge'i arka planda güncelle
    _unreadBadgeTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadUnreadCount(),
    );
    _scrollController.addListener(_onScroll);
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
    _unreadBadgeTimer?.cancel();
    _topPicksTabController
      ..removeListener(_onTopPicksTabControllerChanged)
      ..dispose();
    if (_notificationSvcAttached) {
      NotificationRealtimeService.instance.detach();
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _topPicksScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) return;
      final page = await _messageRepository.getConversations(page: 0, size: 50);
      if (!mounted) return;
      final convCountWithUnread =
          page.content.where((c) => c.unreadCount > 0).length;
      setState(() {
        _unreadMessageCount = convCountWithUnread;
      });
      unawaited(NotificationRealtimeService.instance.refreshUnread());
    } catch (_) {
      // Sessiyon/yetki hatalarında badge'i sadece sıfır bırak
      if (!mounted) return;
      setState(() {
        _unreadMessageCount = 0;
      });
    }
  }

  String _topPicksTabLabel(_TopPicksTab tab) => switch (tab) {
    _TopPicksTab.trendingReviews => 'Trending Reviews',
    _TopPicksTab.weeklyLikes => 'Most Liked',
    _TopPicksTab.forYou => 'For You',
  };

  void _selectTopPicksTab(
    _TopPicksTab tab, {
    bool syncController = true,
    bool forceRefresh = false,
  }) {
    if (!mounted) return;
    final shouldUpdate = tab != _selectedTopPicksTab;
    if (!shouldUpdate && !forceRefresh) return;
    if (shouldUpdate) {
      setState(() {
        _selectedTopPicksTab = tab;
      });
      if (_topPicksScrollController.hasClients) {
        _topPicksScrollController.jumpTo(0);
      }
    }
    final cached = _topPicksByTab[tab] ?? const <ProductDto>[];
    unawaited(_loadTopPicksForTab(tab, showLoadingState: cached.isEmpty));
    if (syncController) {
      final targetIndex = _TopPicksTab.values.indexOf(tab);
      if (_topPicksTabController.index != targetIndex) {
        _topPicksTabController.animateTo(targetIndex);
      }
    }
  }

  void _changeTopPicksTabByDelta(int delta) {
    final currentIndex = _TopPicksTab.values.indexOf(_selectedTopPicksTab);
    final nextIndex = (currentIndex + delta).clamp(
      0,
      _TopPicksTab.values.length - 1,
    );
    if (nextIndex == currentIndex) return;
    _selectTopPicksTab(_TopPicksTab.values[nextIndex]);
  }

  Widget _buildTopPicksHeader() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -120) _changeTopPicksTabByDelta(1);
        else if (velocity > 120) _changeTopPicksTabByDelta(-1);
      },
      child: Row(
        children: _TopPicksTab.values.map((tab) {
          final selected = tab == _selectedTopPicksTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => _selectTopPicksTab(tab),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      letterSpacing: 0.1,
                    ),
                    child: Text(
                      _topPicksTabLabel(tab),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 2.5,
                    width: selected ? 28.0 : 0.0,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _onTopPicksTabControllerChanged() {
    if (_topPicksTabController.indexIsChanging) return;
    final nextTab = _TopPicksTab.values[_topPicksTabController.index];
    _selectTopPicksTab(nextTab, syncController: false);
  }

  Future<void> _loadTopPicksForTab(
    _TopPicksTab tab, {
    bool showLoadingState = false,
  }) async {
    if (_topPicksLoadingTabs.contains(tab)) return;
    final requestId = ++_topPicksRequestSeq;
    _topPicksLatestRequestByTab[tab] = requestId;
    _topPicksLoadingTabs.add(tab);
    if (showLoadingState && mounted) {
      setState(() {
        _isTopPicksLoading = true;
      });
    }
    try {
      final firebaseIdToken = await _sessionHelper.ensureSession();
      late ProductSearchResultDto result;
      switch (tab) {
        case _TopPicksTab.trendingReviews:
          result = await _productRepository.getTrendingReviewsFeed(
            page: 0,
            size: 10,
            firebaseIdToken: firebaseIdToken,
          ).timeout(const Duration(seconds: 8));
          break;
        case _TopPicksTab.weeklyLikes:
          result = await _productRepository.getTrendingLikesWeekFeed(
            page: 0,
            size: 10,
            firebaseIdToken: firebaseIdToken,
          ).timeout(const Duration(seconds: 8));
          break;
        case _TopPicksTab.forYou:
          if (firebaseIdToken == null) {
            result = await _productRepository.getTrendingReviewsFeed(
              page: 0,
              size: 10,
              firebaseIdToken: null,
            ).timeout(const Duration(seconds: 8));
          } else {
            try {
              result = await _productRepository.getPersonalizedFeed(
                page: 0,
                size: 10,
                firebaseIdToken: firebaseIdToken,
              ).timeout(const Duration(seconds: 8));
            } catch (_) {
              // personalized erişilemezse global trende düş.
              result = await _productRepository.getTrendingReviewsFeed(
                page: 0,
                size: 10,
                firebaseIdToken: firebaseIdToken,
              ).timeout(const Duration(seconds: 8));
            }
          }
          break;
      }
      if (!mounted) return;
      if (_topPicksLatestRequestByTab[tab] != requestId) return;
      final products = result.content.take(10).toList();
      _topPicksStaticCache[tab] = products; // statik cache'e kaydet
      setState(() {
        _topPicksByTab[tab] = products;
        _topPicksErrorByTab[tab] = null;
        if (tab == _selectedTopPicksTab) {
          _isTopPicksLoading = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (_topPicksLatestRequestByTab[tab] != requestId) return;
      setState(() {
        _topPicksErrorByTab[tab] = ErrorHandler.getUserFriendlyMessage(e);
      });
    } finally {
      _topPicksLoadingTabs.remove(tab);
      if (mounted) {
        setState(() {
          if (
              tab == _selectedTopPicksTab &&
              _topPicksLatestRequestByTab[tab] == requestId) {
            _isTopPicksLoading = false;
          }
        });
      }
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

      if (!append || page == 0) {
        SearchWarmCache.instance.rememberSeedProducts(_filteredProducts);
      }

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

  void _showCategorySheet(BuildContext ctx) {
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategorySheet(
        tags: _tags,
        selectedIndex: _selectedCategoryIndex,
        onSelectAll: () async {
          Navigator.pop(ctx);
          setState(() {
            _selectedCategoryIndex = -1;
            _selectedSubCategoryIndex = -1;
            _subTags = [];
            _activeCategoryPathPrefix = null;
            _isFiltering = true;
          });
          await _loadProductsPage(0);
        },
        onSelectCategory: (tag, index) {
          Navigator.pop(ctx);
          _onRootCategoryTap(tag, index);
        },
      ),
    );
  }

  Future<void> _onRootCategoryTap(TagDto rootTag, int rootIndex) async {
    setState(() {
      _selectedCategoryIndex = rootIndex;
      _selectedSubCategoryIndex = -1;
      _subTags = [];
      _isLoadingSubTags = true;
      _isFiltering = true;
      _activeCategoryPathPrefix = rootTag.categoryPath;
    });

    // Önce ürünleri yükle (kullanıcı hemen sonuç görsün), alt kategoriler arka planda gelsin
    final token = await _sessionHelper.ensureSession();
    unawaited(
      Future(() async {
        try {
          final childrenResponse = await _tagRepository.getTagChildren(
            rootTag.id,
            token,
          );
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
      }),
    );

    await _loadProductsPage(0);
  }

  /// Product'ın like durumunu ve rating'ini backend'den yeniden çeker
  Future<void> _refreshProductLikeStatus(String productId) async {
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (token == null) return;

      // Product'ı tamamen yeniden yükle (rating ve like durumu ile)
      final updatedProduct = await _productRepository.getProductById(
        productId,
        firebaseIdToken: token,
        bypassCache: true,
      );

      final filteredIndex = _filteredProducts.indexWhere(
        (p) => p.id == productId,
      );
      if (filteredIndex != -1) {
        setState(() {
          _filteredProducts[filteredIndex] = updatedProduct;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadData({bool background = false}) async {
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
        _activeCategoryPathPrefix = null;
        _selectedCategoryIndex = -1;
      });
      SearchWarmCache.instance.rememberRootTags(tags);
      await Future.wait([
        _loadProductsPage(0),
        _loadTopPicksForTab(_selectedTopPicksTab, showLoadingState: !background),
      ]);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (background && _filteredProducts.isNotEmpty) {
          _isLoading = false;
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
    final currentTopPicks =
        _topPicksByTab[_selectedTopPicksTab] ?? const <ProductDto>[];
    final topPicksError = _topPicksErrorByTab[_selectedTopPicksTab];

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
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                /// TOP PICKS SKELETON
                _buildTopPicksHeader(),
                const SizedBox(height: AppSpacing.medium),
                SizedBox(
                  height: 170,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 10,
                    separatorBuilder:
                        (_, __) => const SizedBox(width: AppSpacing.xLarge),
                    itemBuilder:
                        (context, index) => const TopProductCardSkeleton(),
                  ),
                ),
                const SizedBox(height: AppSpacing.medium),

                /// PRODUCTS SKELETON
                ...List.generate(
                  3,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.large),
                    child: ProductCardSkeleton(),
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
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  color: AppColors.primary,
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ConversationListPage(),
                      ),
                    );
                    if (result == true) {
                      await _loadUnreadCount();
                    } else {
                      // Yine de olası yeni mesajlar için refresh et
                      unawaited(_loadUnreadCount());
                    }
                  },
                ),
                if (_unreadMessageCount > 0)
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
                        _unreadMessageCount > 9
                            ? '9+'
                            : _unreadMessageCount.toString(),
                        style: AppTextStyles.bodySecondary.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopPicksHeader(),
              const SizedBox(height: AppSpacing.medium),
              if (topPicksError != null && currentTopPicks.isEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.large,
                    vertical: AppSpacing.medium,
                  ),
                  margin: const EdgeInsets.only(bottom: AppSpacing.small),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.75),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          topPicksError,
                          style: AppTextStyles.bodySecondary,
                        ),
                      ),
                      TextButton(
                        onPressed:
                            () => _selectTopPicksTab(
                              _selectedTopPicksTab,
                              forceRefresh: true,
                            ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(
                height: 170,
                child:
                    _isTopPicksLoading && currentTopPicks.isEmpty
                        ? ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: 10,
                          separatorBuilder:
                              (_, __) => const SizedBox(width: AppSpacing.xLarge),
                          itemBuilder:
                              (context, index) => const TopProductCardSkeleton(),
                        )
                        : ListView.separated(
                          controller: _topPicksScrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: currentTopPicks.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(width: AppSpacing.xLarge),
                          itemBuilder: (context, index) {
                            final product = currentTopPicks[index];
                            return TopProductList(
                              product: product,
                              rank: index + 1,
                            );
                          },
                        ),
              ),
              if (!_isTopPicksLoading && currentTopPicks.isEmpty) ...[
                const SizedBox(height: AppSpacing.small),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.large,
                    vertical: AppSpacing.medium,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.75),
                    ),
                  ),
                  child: Text(
                    'No products in this feed right now.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.medium),
              // Kategori filtre butonu — outer padding outer ScrollView'dan geliyor
              Row(
                children: [
                  _CategoryFilterButton(
                    label: _selectedCategoryIndex == -1
                        ? 'All Categories'
                        : _tags[_selectedCategoryIndex].name,
                    isActive: _selectedCategoryIndex != -1,
                    onTap: _tags.isEmpty
                        ? null
                        : () => _showCategorySheet(context),
                  ),
                  if (_selectedCategoryIndex != -1) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        setState(() {
                          _selectedCategoryIndex = -1;
                          _selectedSubCategoryIndex = -1;
                          _subTags = [];
                          _activeCategoryPathPrefix = null;
                          _isFiltering = true;
                        });
                        await _loadProductsPage(0);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Alt kategori satırı (AnimatedSize ile yumuşak)
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _selectedCategoryIndex != -1
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 10),
                          if (_isLoadingSubTags)
                            SizedBox(
                              height: 32,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: EdgeInsets.zero,
                                itemCount: 5,
                                separatorBuilder:
                                    (_, __) => const SizedBox(width: 8),
                                itemBuilder:
                                    (_, __) => const SkeletonLoader(
                                      width: 64,
                                      height: 32,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(16),
                                      ),
                                    ),
                              ),
                            )
                          else if (_subTags.isNotEmpty)
                            SizedBox(
                              height: 32,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: EdgeInsets.zero,
                                itemCount: _subTags.length + 1,
                                separatorBuilder:
                                    (_, __) => const SizedBox(width: 6),
                                itemBuilder: (context, i) {
                                  if (i == 0) {
                                    return _CategoryChip(
                                      title: 'All',
                                      selected:
                                          _selectedSubCategoryIndex == -1,
                                      isSubCategory: true,
                                      onTap: () async {
                                        final rootTag =
                                            _tags[_selectedCategoryIndex];
                                        setState(() {
                                          _selectedSubCategoryIndex = -1;
                                          _activeCategoryPathPrefix =
                                              rootTag.categoryPath;
                                          _isFiltering = true;
                                        });
                                        await _loadProductsPage(0);
                                      },
                                    );
                                  }
                                  final subIndex = i - 1;
                                  final subTag = _subTags[subIndex];
                                  return _CategoryChip(
                                    title: subTag.name,
                                    selected:
                                        subIndex == _selectedSubCategoryIndex,
                                    isSubCategory: true,
                                    onTap: () async {
                                      setState(() {
                                        _selectedSubCategoryIndex = subIndex;
                                        _activeCategoryPathPrefix =
                                            subTag.categoryPath;
                                        _isFiltering = true;
                                      });
                                      await _loadProductsPage(0);
                                    },
                                  );
                                },
                              ),
                            ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xxLarge),
              _isFiltering
                  // Kategori / sayfa değişirken, gerçek grid yapısına benzeyen skeleton grid göster
                  ? GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSpacing.xLarge,
                          mainAxisSpacing: AppSpacing.xLarge,
                          childAspectRatio: 0.60,
                        ),
                    itemCount: 4,
                    itemBuilder:
                        (context, index) => const ProductCardSkeleton(),
                  )
                  : _filteredProducts.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxLarge),
                      child: Text(
                        'No products found',
                        style: AppTextStyles.bodySecondary,
                      ),
                    ),
                  )
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: AppSpacing.xLarge,
                              mainAxisSpacing: AppSpacing.xLarge,
                              childAspectRatio: 0.60,
                            ),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return ProductCard(
                            key: ValueKey(
                              'product_${product.id}_${product.averageRating}',
                            ),
                            productId: product.id,
                            imageUrl: product.imageURL,
                            title: product.name,
                            category: product.tag.name,
                            categoryPath: product.tag.categoryPath,
                            rating: product.averageRating ?? 0.0,
                            desc: product.description ?? '',
                            isFavorite: product.isLiked ?? false,
                            loadReviewCount: true,
                            onTap: () async {
                              final updatedProduct =
                                  await Navigator.push<ProductDto>(
                                    context,
                                    SlideRightRoute(
                                      page: ReviewPage(product: product),
                                    ),
                                  );
                              if (updatedProduct != null) {
                                final filteredIndex = _filteredProducts
                                    .indexWhere(
                                      (p) => p.id == updatedProduct.id,
                                    );
                                if (filteredIndex != -1) {
                                  setState(() {
                                    _filteredProducts[filteredIndex] =
                                        updatedProduct;
                                  });
                                }
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
                                    content: Text(
                                      'Please login to like products',
                                    ),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                                return;
                              }
                              final filteredIndex = _filteredProducts
                                  .indexWhere((p) => p.id == product.id);
                              if (filteredIndex != -1) {
                                final currentLikeStatus =
                                    _filteredProducts[filteredIndex].isLiked ??
                                    false;
                                setState(() {
                                  _filteredProducts[filteredIndex] =
                                      _filteredProducts[filteredIndex].copyWith(
                                        isLiked: !currentLikeStatus,
                                      );
                                });
                              }
                              try {
                                final token =
                                    await _sessionHelper.getTokenAndSetHeader();
                                if (token == null) {
                                  throw Exception(
                                    'Failed to get Firebase ID token',
                                  );
                                }
                                final newLikeStatus =
                                    await _interactionRepository
                                        .toggleProductLike(token, product.id);
                                if (filteredIndex != -1) {
                                  setState(() {
                                    _filteredProducts[filteredIndex] =
                                        _filteredProducts[filteredIndex]
                                            .copyWith(isLiked: newLikeStatus);
                                  });
                                }
                              } catch (e) {
                                if (filteredIndex != -1) {
                                  setState(() {
                                    _filteredProducts[filteredIndex] =
                                        _filteredProducts[filteredIndex]
                                            .copyWith(isLiked: product.isLiked);
                                  });
                                }
                                if (mounted) {
                                  final errorMessage =
                                      ErrorHandler.getUserFriendlyMessage(e);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(errorMessage),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
                      if (_isLoadingMore)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.large,
                          ),
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
                  ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}

/// CATEGORY CHIP
class _CategoryChip extends StatelessWidget {
  final String title;
  final bool selected;
  final bool isSubCategory;
  final VoidCallback? onTap;

  const _CategoryChip({
    required this.title,
    this.selected = false,
    this.isSubCategory = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isSubCategory) {
      // Alt kategori: solid fill pill
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.border,
              width: 1.1,
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: 0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // Ana kategori: underline tab stili
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 13.5,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: 2.5,
              width: selected ? 20.0 : 0.0,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Kategori filtre butonu ───────────────────────────────────────────────────

class _CategoryFilterButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _CategoryFilterButton({
    required this.label,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? AppColors.primary
                : AppColors.border,
            width: 1.3,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 15,
              color: isActive ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 17,
              color: isActive
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Kategori seçim bottom sheet ─────────────────────────────────────────────

class _CategorySheet extends StatelessWidget {
  final List<TagDto> tags;
  final int selectedIndex;
  final VoidCallback onSelectAll;
  final void Function(TagDto, int) onSelectCategory;

  const _CategorySheet({
    required this.tags,
    required this.selectedIndex,
    required this.onSelectAll,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xLarge,
            ),
            child: Text(
              'Browse by Category',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          LimitedBox(
            maxHeight: 340,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _SheetRow(
                  label: 'All Categories',
                  selected: selectedIndex == -1,
                  onTap: onSelectAll,
                ),
                ...List.generate(tags.length, (i) {
                  return _SheetRow(
                    label: tags[i].name,
                    selected: i == selectedIndex,
                    onTap: () => onSelectCategory(tags[i], i),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SheetRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xLarge,
          vertical: 13,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? AppColors.primary
                      : AppColors.textPrimary,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

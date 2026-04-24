import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/cache/following_id_set_cache.dart';
import '../../../core/cache/search_warm_cache.dart';
import '../../../core/utils/error_handler.dart';
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

  /// GET /api/reviews/top-reviewers — giriş yapmışken dolar
  List<TopReviewerDto> _topReviewers = [];
  bool _loadingTopReviewers = false;

  /// Takip / takipçi (arama havuzu — giriş gerekir)
  List<ConversationUserDto> _socialSearchUsers = [];

  /// Aktif sorgu için eşleşen profiller (kullanıcı adı metni)
  List<_ProfileSearchEntry> _profileSearchMatches = [];

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
    _loadInitialData();
    unawaited(_loadSocialGraphForSearch());
    _scheduleTopReviewerRefresh();
  }

  /// Profil adına göre yerel eşleşme: top reviewers + takip edilen / takipçi.
  List<_ProfileSearchEntry> _computeProfileMatches(String q) {
    if (q.isEmpty) return const [];
    final seen = <String>{};
    final merged = <_ProfileSearchEntry>[];

    void add(
      String userId,
      String userName,
      String? imageUrl, {
      String? subtitle,
    }) {
      final id = userId.trim();
      final name = userName.trim();
      if (id.isEmpty || name.isEmpty) return;
      if (!seen.add(id)) return;
      merged.add(
        _ProfileSearchEntry(
          userId: id,
          userName: name,
          profileImageUrl: imageUrl,
          subtitle: subtitle,
        ),
      );
    }

    for (final t in _topReviewers) {
      add(
        t.userId,
        t.userName,
        t.profileImageUrl,
        subtitle: t.reviewCount > 0 ? '${t.reviewCount} reviews' : null,
      );
    }
    for (final c in _socialSearchUsers) {
      if (c.id <= 0) continue;
      add(
        c.id.toString(),
        c.username,
        c.profilePhotoUrl,
        subtitle: 'In your network',
      );
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
      _profileSearchMatches = _computeProfileMatches(q);
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
    } catch (_) {}
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
    } catch (_) {
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
      setProductCardSocialCaches(
        productId,
        likeCount: like,
        reviewCount: filterVisibleReviews(reviews).length,
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
    } catch (_) {}
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
    if (_notificationSvcAttached) {
      NotificationRealtimeService.instance.detach();
    }
    _topReviewersRefreshTimer?.cancel();
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
    });

    try {
      // Token opsiyonel: kategoriler ve ürün listesi token olmadan da döner
      final token = await _sessionHelper.ensureSession();
      _firebaseIdToken = token;

      // Önce sadece kategorileri yükle → ekran hemen açılsın
      List<TagDto> rootTags = [];
      try {
        rootTags = await _tagRepository.getRootTags(token);
      } catch (_) {}

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
      } catch (_) {
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
      } catch (_) {}
      if (rootTags.isNotEmpty) {
        SearchWarmCache.instance.rememberRootTags(rootTags);
        if (mounted) {
          setState(() {
            _rootCategories = rootTags;
            _currentCategories = rootTags;
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
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _refreshSearchPage() async {
    await Future.wait<void>([
      _refreshInitialDataInBackground(),
      _loadTopReviewers(force: true, silentLoading: true),
      _loadSocialGraphForSearch(),
    ]);
    final q = _searchController.text.trim();
    if (q.isNotEmpty && mounted) {
      await _onSearchChanged(q);
    }
  }

  Future<void> _openCategory(TagDto category) async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      final response = await _tagRepository.getTagChildren(category.id, _firebaseIdToken);
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
      ReviewPrefetchService.instance.prefetchForProducts(
        products,
        maxCount: 6,
      );
    } catch (e) {
      setState(() {
        _isLoadingCategories = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getUserFriendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
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

  Future<void> _onSearchChanged(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    _activeQuery = normalizedQuery;
    if (normalizedQuery.isEmpty) {
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
      _isSearching = true;
      _showCategoryResults = false;
      _activeLeafCategory = null;
    });

    try {
      final results = _allProducts.where((product) {
        final productName = product.name.toLowerCase();
        final tagName = product.tag.name.toLowerCase();
        final tagPathSegments = (product.tag.categoryPath ?? '')
            .toLowerCase()
            .split('.')
            .where((segment) => segment.isNotEmpty)
            .toList();

        // Match only by product title OR product's own tags (name + category path segments).
        final nameMatch = productName.contains(normalizedQuery);
        final ownTagMatch = tagName.contains(normalizedQuery) ||
            tagPathSegments.any((segment) => segment.contains(normalizedQuery));

        return nameMatch || ownTagMatch;
      }).toList();

      if (!mounted || _activeQuery != normalizedQuery) return;
      setState(() {
        _searchResults = results;
        _profileSearchMatches = _computeProfileMatches(normalizedQuery);
        _isSearching = false;
      });
      ReviewPrefetchService.instance.prefetchForProducts(
        results,
        maxCount: 6,
      );
    } catch (e) {
      if (!mounted || _activeQuery != normalizedQuery) return;
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getUserFriendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: 'Refresh',
            onPressed: () => unawaited(_refreshSearchPage()),
          ),
        ],
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
              : Padding(
                  padding: const EdgeInsets.all(AppSpacing.xLarge),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _searchFocusNode.hasFocus
                                ? AppColors.primary
                                : AppColors.border,
                            width: _searchFocusNode.hasFocus ? 1.5 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
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
                                      _onSearchChanged('');
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
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      if (_searchController.text.trim().isEmpty && !_showCategoryResults) ...[
                        if (_loadingTopReviewers)
                          const Padding(
                            padding: EdgeInsets.only(bottom: AppSpacing.medium),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          )
                        else if (_topReviewers.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(top: 8, bottom: 10),
                            child: Text(
                              'Top 5 Reviewers',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(
                            height: 106,
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
                                      data: t,
                                      onTap: hasData
                                          ? () {
                                              if (t!.userId.isEmpty) return;
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
                        ],
                      ],
                      if ((_searchController.text.trim().isEmpty && !_showCategoryResults) &&
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
                                              TextButton.icon(
                                                onPressed: _goBackCategoryLevel,
                                                style: TextButton.styleFrom(
                                                  foregroundColor: AppColors.primary,
                                                ),
                                                icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                                                label: const Text('Back'),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _activeLeafCategory?.name ?? 'Category',
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
                                          if (_categoryPath.isNotEmpty)
                                            Row(
                                              children: [
                                                TextButton.icon(
                                                  onPressed: _goBackCategoryLevel,
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: AppColors.primary,
                                                  ),
                                                  icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                                                  label: const Text('Back'),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _categoryPath.map((e) => e.name).join(' > '),
                                                    style: AppTextStyles.bodySecondary,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          if (_categoryPath.isEmpty) ...[
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 10, left: 2),
                                              child: Text(
                                                'Browse Categories',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textSecondary,
                                                  letterSpacing: 0.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                          Expanded(
                                            child: ListView.separated(
                                              padding: EdgeInsets.zero,
                                              itemCount: _currentCategories.length,
                                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                                              itemBuilder: (context, index) {
                                                final category = _currentCategories[index];
                                                return Material(
                                                  color: AppColors.surface,
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: InkWell(
                                                    onTap: () => _openCategory(category),
                                                    borderRadius: BorderRadius.circular(12),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(color: AppColors.border, width: 1),
                                                      ),
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 13,
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Container(
                                                            width: 6,
                                                            height: 6,
                                                            decoration: const BoxDecoration(
                                                              color: AppColors.primary,
                                                              shape: BoxShape.circle,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 12),
                                                          Expanded(
                                                            child: Text(
                                                              category.name,
                                                              style: const TextStyle(
                                                                fontSize: 15,
                                                                fontWeight: FontWeight.w500,
                                                                color: AppColors.textPrimary,
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
                    ],
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
    this.subtitle,
  });

  final String userId;
  final String userName;
  final String? profileImageUrl;
  final String? subtitle;
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
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 172,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 1),
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
                    if (entry.subtitle != null && entry.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        entry.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
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
    required this.data,
    required this.onTap,
  });

  final TopReviewerDto? data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final username = (data?.userName ?? '').trim();
    final reviewLabel = data == null
        ? ' '
        : '${data!.reviewCount} ${data!.reviewCount == 1 ? 'review' : 'reviews'}';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: ProfileAvatarImage(
                    size: 40,
                    imageUrl: data?.profileImageUrl,
                    fallbackInitial: username.isNotEmpty ? username : '?',
                  ),
                ),
              ),
              const SizedBox(height: 4),
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
              const SizedBox(height: 1),
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
      ),
    );
  }
}


import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/cache/search_warm_cache.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/session_helper.dart';
import '../../../core/notifications/notification_realtime_service.dart';
import '../../../core/widgets/main_bottom_nav_items.dart';
import '../../../features/activity/presentation/activity_page.dart';
import '../data/models/product_dto.dart';
import '../data/models/tag_dto.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/services/review_prefetch_service.dart';
import '../widgets/product_card.dart';
import '../../../core/widgets/skeleton_loader.dart';
import 'home_page.dart';
import 'friend_feed_page.dart';
import 'profile/pages/profile_page.dart';
import 'review/pages/review_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final ProductRepository _productRepository = ProductRepository();
  final TagRepository _tagRepository = TagRepository();
  final SessionHelper _sessionHelper = SessionHelper();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hookNotificationsIfSignedIn());
    });
    _searchFocusNode.addListener(() {
      setState(() {});
    });
    _loadInitialData();
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

  Future<void> _onSearchChanged(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    _activeQuery = normalizedQuery;
    if (normalizedQuery.isEmpty) {
      setState(() {
        _searchResults = [];
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
                            hintText: 'Search products or categories...',
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
                      const SizedBox(height: AppSpacing.xLarge),
                      Expanded(
                        child: _searchController.text.trim().isNotEmpty
                            ? (_isSearching
                            ? const Center(child: ListLoadMoreSkeleton())
                            : _searchResults.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No matching products found',
                                          style: AppTextStyles.bodySecondary,
                                        ),
                                      )
                                    : GridView.builder(
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
                                            productId: product.id,
                                            imageUrl: product.imageURL,
                                            title: product.name,
                                            category: product.tag.name,
                                            categoryPath: product.tag.categoryPath,
                                            rating: product.averageRating ?? 0.0,
                                            desc: product.description ?? '',
                                            isFavorite: product.isLiked ?? false,
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => ReviewPage(product: product),
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      ))
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
                                                        productId: product.id,
                                                        imageUrl: product.imageURL,
                                                        title: product.name,
                                                        category: product.tag.name,
                                                        categoryPath: product.tag.categoryPath,
                                                        rating: product.averageRating ?? 0.0,
                                                        desc: product.description ?? '',
                                                        isFavorite: product.isLiked ?? false,
                                                        onTap: () {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) => ReviewPage(product: product),
                                                            ),
                                                          );
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
                                              separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5),
                                              itemBuilder: (context, index) {
                                                final category = _currentCategories[index];
                                                return InkWell(
                                                  onTap: () => _openCategory(category),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 11,
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


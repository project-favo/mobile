import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_chip_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/session_helper.dart';
import '../../../core/widgets/custom_refresh_indicator.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/routes/custom_page_transitions.dart';
import '../widgets/product_card.dart';
import '../widgets/top_product_card.dart';
import 'search_page.dart';
import 'profile/pages/profile_page.dart';
import 'review/pages/review_page.dart';
import '../data/repositories/tag_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/interaction_repository.dart';
import '../data/models/tag_dto.dart';
import '../data/models/product_dto.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  int _selectedCategoryIndex = -1; // -1 means "All", 0+ means selected category
  int _selectedSubCategoryIndex = -1; // -1 means none
  final TagRepository _tagRepository = TagRepository();
  final ProductRepository _productRepository = ProductRepository();
  final InteractionRepository _interactionRepository = InteractionRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  
  List<TagDto> _tags = [];
  List<TagDto> _subTags = [];
  List<ProductDto> _allProducts = []; // Deprecated: kept for compatibility
  List<ProductDto> _filteredProducts = []; // Current page products
  int _currentPage = 0;
  int _totalPages = 0;
  String? _activeCategoryPathPrefix;
  bool _isLoading = true;
  bool _isFiltering = false; // Kategori filtreleme yapılırken
  bool _isLoadingSubTags = false;
  String? _errorMessage;

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
      currentIndex: _currentIndex,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      onTap: (index) {
        if (index == 1) {
          Navigator.pushReplacement(
            context,
            _noAnimationRoute(const SearchPage()),
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

        setState(() {
          _currentIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
        BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
        BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border), label: 'Favorites'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Kategoriye göre ürünleri filtreler
  /// Yeni backend search/pagination mantığı:
  /// - All: /api/products/home?page=X&size=Y
  /// - Category: /api/products/search?categoryPathPrefix=...&page=X&size=Y
  Future<void> _loadProductsPage(int page) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated. Please login first.');
      }

      final firebaseIdToken = await _sessionHelper.ensureSession();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      if (kDebugMode) {
        debugPrint(
            'HomePage - Loading page $page, categoryPathPrefix=$_activeCategoryPathPrefix');
      }

      final result = _activeCategoryPathPrefix == null
          ? await _productRepository.getHomeFeed(
              page: page,
              size: 20,
              firebaseIdToken: firebaseIdToken,
            )
          : await _productRepository.searchProducts(
              categoryPathPrefix: _activeCategoryPathPrefix!,
              page: page,
              size: 20,
              firebaseIdToken: firebaseIdToken,
            );

      if (!mounted) return;

      setState(() {
        _filteredProducts = result.content;
        _currentPage = result.number;
        _totalPages = result.totalPages;
        _isFiltering = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HomePage - Error loading products page: $e');
      }
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
    });

    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      final childrenResponse =
          await _tagRepository.getTagChildren(rootTag.id, token);

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
      );

      if (kDebugMode) {
        debugPrint('HomePage - Product refreshed: ${updatedProduct.name}, Rating: ${updatedProduct.averageRating}, Liked: ${updatedProduct.isLiked}');
      }

      final filteredIndex = _filteredProducts.indexWhere((p) => p.id == productId);
      if (filteredIndex != -1) {
        setState(() {
          _filteredProducts[filteredIndex] = updatedProduct;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to refresh product like status: $e');
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get Firebase ID token for authentication (required for tag endpoints)
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated. Please login first.');
      }


      // Ensure backend session is established (only if needed)
      final firebaseIdToken = await _sessionHelper.ensureSession();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Fetch tags (requires authentication)
      final tags = await _tagRepository.getRootTags(firebaseIdToken);
      _tags = tags;
      _activeCategoryPathPrefix = null;
      await _loadProductsPage(0);

      if (mounted) {
        setState(() {
          _selectedCategoryIndex = -1; // "All" selected
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _allProducts.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false, // Geri butonu olmasın
          title: Text(
            'FAVO',
            style: AppTextStyles.HomeHeader.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: AppColors.primary.withOpacity(0.3),
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          centerTitle: true,
        ),
        body: CustomRefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// TOP 10 SKELETON
                const Text(
                  'Top 10 Products',
                  style: AppTextStyles.heading2,
                ),
                const SizedBox(height: AppSpacing.large),
                SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 10,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppSpacing.xLarge),
                    itemBuilder: (context, index) => const TopProductCardSkeleton(),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxLarge),
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
          automaticallyImplyLeading: false, // Geri butonu olmasın
          title: Text(
            'FAVO',
            style: AppTextStyles.HomeHeader.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: AppColors.primary.withOpacity(0.3),
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
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
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: AppColors.error,
                ),
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

    /// TOP 10 PRODUCTS - Use first 10 products from filtered products
    final top10Products = _filteredProducts.take(10).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'FAVO',
          style: AppTextStyles.HomeHeader.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            shadows: [
              Shadow(
                color: AppColors.primary.withOpacity(0.3),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble),
            color: AppColors.primary,
            onPressed: () {},
          ),
        ],
      ),
      body: CustomRefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Top 10 Products',
                style: AppTextStyles.heading2,
              ),
              const SizedBox(height: AppSpacing.large),
              SizedBox(
                height: 240,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: top10Products.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.xLarge),
                  itemBuilder: (context, index) {
                    final product = top10Products[index];
                    return TopProductList(
                      product: product,
                      rank: index + 1,
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xxLarge),
              SizedBox(
                height: AppSpacing.categoryChipHeight,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _CategoryChip(
                      title: 'All',
                      selected: _selectedCategoryIndex == -1,
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
                    ),
                    ..._tags.asMap().entries.map<Widget>((entry) {
                      final index = entry.key;
                      final tag = entry.value;
                      return _CategoryChip(
                        title: tag.name,
                        selected: index == _selectedCategoryIndex,
                        onTap: () => _onRootCategoryTap(tag, index),
                      );
                    }),
                  ],
                ),
              ),
              if (_selectedCategoryIndex != -1) ...[
                const SizedBox(height: AppSpacing.large),
                if (_isLoadingSubTags)
                  // Alt kategori skeleton'ları: ana chip'lerle aynı hizada, shimmer'lı
                  SizedBox(
                    height: AppSpacing.categoryChipHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 4,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.large),
                      itemBuilder: (context, index) => const SkeletonLoader(
                        width: 70,
                        height: AppSpacing.categoryChipHeight - 8,
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                    ),
                  )
                else if (_subTags.isNotEmpty)
                  SizedBox(
                    height: AppSpacing.categoryChipHeight,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _CategoryChip(
                          title: 'All',
                          selected: _selectedSubCategoryIndex == -1,
                          isSubCategory: true,
                          onTap: () async {
                            final rootTag = _tags[_selectedCategoryIndex];
                            setState(() {
                              _selectedSubCategoryIndex = -1;
                              _activeCategoryPathPrefix =
                                  rootTag.categoryPath;
                              _isFiltering = true;
                            });
                            await _loadProductsPage(0);
                          },
                        ),
                        ..._subTags.asMap().entries.map<Widget>((entry) {
                          final subIndex = entry.key;
                          final subTag = entry.value;
                          return _CategoryChip(
                            title: subTag.name,
                            selected: subIndex == _selectedSubCategoryIndex,
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
                        }).toList(),
                      ],
                    ),
                  ),
              ],
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
                        childAspectRatio: 0.6,
                      ),
                      itemCount: 4,
                      itemBuilder: (context, index) =>
                          const ProductCardSkeleton(),
                    )
                  : _filteredProducts.isEmpty
                      ? Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.all(AppSpacing.xxLarge),
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
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: AppSpacing.xLarge,
                                mainAxisSpacing: AppSpacing.xLarge,
                                childAspectRatio: 0.6,
                              ),
                              itemCount: _filteredProducts.length,
                              itemBuilder: (context, index) {
                                final product = _filteredProducts[index];
                                return ProductCard(
                                  key: ValueKey(
                                    'product_${product.id}_${product.isLiked}_${product.averageRating}',
                                  ),
                                  productId: product.id,
                                  imageUrl: product.imageURL,
                                  title: product.name,
                                  category: product.tag.name,
                                  rating: product.averageRating ?? 0.0,
                                  desc: product.description ?? '',
                                  isFavorite: product.isLiked ?? false,
                                  onTap: () async {
                                    final updatedProduct =
                                        await Navigator.push<ProductDto>(
                                      context,
                                      SlideRightRoute(
                                        page: ReviewPage(product: product),
                                      ),
                                    );
                                    if (updatedProduct != null) {
                                      final filteredIndex =
                                          _filteredProducts.indexWhere(
                                        (p) => p.id == updatedProduct.id,
                                      );
                                      if (filteredIndex != -1) {
                                        setState(() {
                                          _filteredProducts[filteredIndex] =
                                              updatedProduct;
                                        });
                                      }
                                    } else {
                                      await _refreshProductLikeStatus(
                                        product.id,
                                      );
                                    }
                                  },
                                  onFavoriteTap: () async {
                                    final user =
                                        FirebaseAuth.instance.currentUser;
                                    if (user == null) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Please login to like products',
                                          ),
                                          backgroundColor:
                                              AppColors.error,
                                        ),
                                      );
                                      return;
                                    }
                                    final filteredIndex =
                                        _filteredProducts.indexWhere(
                                      (p) => p.id == product.id,
                                    );
                                    if (filteredIndex != -1) {
                                      final currentLikeStatus =
                                          _filteredProducts[filteredIndex]
                                                  .isLiked ??
                                              false;
                                      setState(() {
                                        _filteredProducts[filteredIndex] =
                                            _filteredProducts[filteredIndex]
                                                .copyWith(
                                          isLiked: !currentLikeStatus,
                                        );
                                      });
                                    }
                                    try {
                                      final token =
                                          await _sessionHelper
                                              .getTokenAndSetHeader();
                                      if (token == null) {
                                        throw Exception(
                                          'Failed to get Firebase ID token',
                                        );
                                      }
                                      final newLikeStatus =
                                          await _interactionRepository
                                              .toggleProductLike(
                                        token,
                                        product.id,
                                      );
                                      if (kDebugMode) {
                                        debugPrint(
                                          'HomePage - Like toggled: Product ${product.id}, New status: $newLikeStatus',
                                        );
                                      }
                                      if (filteredIndex != -1) {
                                        setState(() {
                                          _filteredProducts[filteredIndex] =
                                              _filteredProducts[filteredIndex]
                                                  .copyWith(
                                            isLiked: newLikeStatus,
                                          );
                                        });
                                      }
                                    } catch (e) {
                                      if (filteredIndex != -1) {
                                        setState(() {
                                          _filteredProducts[filteredIndex] =
                                              _filteredProducts[filteredIndex]
                                                  .copyWith(
                                            isLiked: product.isLiked,
                                          );
                                        });
                                      }
                                      if (mounted) {
                                        final errorMessage =
                                            ErrorHandler
                                                .getUserFriendlyMessage(
                                          e,
                                        );
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(errorMessage),
                                            backgroundColor:
                                                AppColors.error,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: AppSpacing.large),
                            if (_totalPages > 1)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    onPressed: _currentPage > 0 &&
                                            !_isFiltering
                                        ? () async {
                                            setState(() {
                                              _isFiltering = true;
                                            });
                                            await _loadProductsPage(
                                              _currentPage - 1,
                                            );
                                          }
                                        : null,
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Text(
                                    'Page ${_currentPage + 1} of $_totalPages',
                                    style:
                                        AppTextStyles.bodySecondary,
                                  ),
                                  IconButton(
                                    onPressed: _currentPage <
                                                _totalPages - 1 &&
                                            !_isFiltering
                                        ? () async {
                                            setState(() {
                                              _isFiltering = true;
                                            });
                                            await _loadProductsPage(
                                              _currentPage + 1,
                                            );
                                          }
                                        : null,
                                    icon:
                                        const Icon(Icons.chevron_right),
                                  ),
                                ],
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
    final decoration =
        AppChipStyles.categoryChipDecoration(selected: selected);

    final textStyle =
        AppChipStyles.categoryChipText(selected: selected).copyWith(
      fontSize: isSubCategory ? 12 : null,
    );

    final horizontalPadding =
        isSubCategory ? AppSpacing.large : AppSpacing.xLarge;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.large),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          alignment: Alignment.center,
          decoration: decoration,
          child: Text(
            title,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

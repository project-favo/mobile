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
  final TagRepository _tagRepository = TagRepository();
  final ProductRepository _productRepository = ProductRepository();
  final InteractionRepository _interactionRepository = InteractionRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  
  List<TagDto> _tags = [];
  List<ProductDto> _allProducts = []; // Tüm ürünler (filtrelenmemiş)
  List<ProductDto> _filteredProducts = []; // Filtrelenmiş ürünler
  bool _isLoading = true;
  bool _isFiltering = false; // Kategori filtreleme yapılırken
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Kategoriye göre ürünleri filtreler
  /// Seçilen tag'in tüm leaf tag'lerindeki product'ları toplar
  Future<void> _filterProductsByCategory(String tagId, int categoryIndex) async {
    setState(() {
      _selectedCategoryIndex = categoryIndex;
      _isFiltering = true;
      _filteredProducts = []; // Filtreleme başlarken listeyi temizle
    });

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
        debugPrint('HomePage - Filtering by category: $tagId');
      }

      // Önce direkt olarak bu tag'e bağlı product'ları al ve hemen göster (hızlı feedback)
      final directProducts = await _productRepository.getProductsByTagId(
        tagId,
        firebaseIdToken: firebaseIdToken,
      ).catchError((e) {
        if (kDebugMode) {
          debugPrint('HomePage - Failed to get direct products: $e');
        }
        return <ProductDto>[];
      });

      // Direkt product'ları hemen göster (kullanıcı hızlı feedback alsın)
      if (directProducts.isNotEmpty) {
        setState(() {
          _filteredProducts = directProducts;
          // _isFiltering hala true, arka planda leaf tag'lerden product'ları toplayacağız
        });
      }

      // Arka planda leaf tag'lerden product'ları topla (non-blocking)
      _tagRepository.getAllLeafTagIds(tagId, firebaseIdToken).then((leafTagIds) {
        if (leafTagIds.isEmpty) {
          // Leaf tag yoksa, direkt product'ları göster
          setState(() {
            _isFiltering = false;
          });
          return;
        }

        if (kDebugMode) {
          debugPrint('HomePage - Found ${leafTagIds.length} leaf tags, fetching products...');
        }

        // PARALLEL: Her leaf tag için product'ları aynı anda topla
        Future.wait(
          leafTagIds.map((leafTagId) => 
            _productRepository.getProductsByTagId(
              leafTagId,
              firebaseIdToken: firebaseIdToken,
            ).catchError((e) {
              if (kDebugMode) {
                debugPrint('Failed to get products for tag $leafTagId: $e');
              }
              return <ProductDto>[];
            })
          ),
        ).then((leafProductsResults) {
          // Tüm product'ları topla (direkt + leaf tag'lerden)
          final allFilteredProducts = <ProductDto>[];
          allFilteredProducts.addAll(directProducts);
          
          for (final products in leafProductsResults) {
            allFilteredProducts.addAll(products);
          }

          // Duplicate product'ları kaldır
          final uniqueProducts = <String, ProductDto>{};
          for (final product in allFilteredProducts) {
            uniqueProducts[product.id] = product;
          }

          if (mounted) {
            setState(() {
              _filteredProducts = uniqueProducts.values.toList();
              _isFiltering = false;
            });

            if (kDebugMode) {
              debugPrint('HomePage - Total filtered products count: ${_filteredProducts.length}');
            }
          }
        }).catchError((e) {
          if (kDebugMode) {
            debugPrint('HomePage - Error fetching leaf products: $e');
          }
          if (mounted) {
            setState(() {
              _isFiltering = false;
            });
          }
        });
      }).catchError((e) {
        if (kDebugMode) {
          debugPrint('HomePage - Failed to get leaf tags: $e');
        }
        // Leaf tag'ler alınamazsa, direkt product'ları göster
        if (mounted) {
          setState(() {
            _isFiltering = false;
          });
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HomePage - Error filtering products: $e');
      }
      setState(() {
        _isFiltering = false;
        _filteredProducts = []; // Hata durumunda boş liste
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to filter products: ${ErrorHandler.getUserFriendlyMessage(e)}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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

      // Product listesinde bu product'ı bul ve güncelle
      final allIndex = _allProducts.indexWhere((p) => p.id == productId);
      final filteredIndex = _filteredProducts.indexWhere((p) => p.id == productId);
      
      if (allIndex != -1) {
        setState(() {
          _allProducts[allIndex] = updatedProduct;
          // Eğer filtrelenmiş listede de varsa güncelle
          if (filteredIndex != -1) {
            _filteredProducts[filteredIndex] = updatedProduct;
          }
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

      // Fetch tags (requires authentication) and products (with rating and like info)
      final tags = await _tagRepository.getRootTags(firebaseIdToken);
      final products = await _productRepository.getAllProducts(firebaseIdToken: firebaseIdToken);
      
      setState(() {
        _tags = tags;
        _allProducts = products;
        _filteredProducts = products; // Başlangıçta tüm ürünleri göster
        _selectedCategoryIndex = -1; // "Tümü" seçili
        _isLoading = false;
      });
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
      );
    }

    /// TOP 10 PRODUCTS - Use first 10 products from filtered products
    final top10Products = _filteredProducts.take(10).toList();

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
              /// TOP 10
              const Text(
                'Top 10 Products',
                style: AppTextStyles.heading2,
              ),
              const SizedBox(height: AppSpacing.large),

              SizedBox(
                // Top 10 kartları için yükseklik (artık daha yüksek olabilir)
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

            /// CATEGORIES
            SizedBox(
              height: AppSpacing.categoryChipHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // "Tümü" seçeneği
                  _CategoryChip(
                    title: 'All',
                    selected: _selectedCategoryIndex == -1,
                    onTap: () {
                      setState(() {
                        _selectedCategoryIndex = -1;
                        _filteredProducts = _allProducts;
                      });
                    },
                  ),
                  // Kategoriler
                  ..._tags.asMap().entries.map<Widget>((entry) {
                    final index = entry.key;
                    final tag = entry.value;
                    return _CategoryChip(
                      title: tag.name,
                      selected: index == _selectedCategoryIndex,
                      onTap: () => _filterProductsByCategory(tag.id, index),
                    );
                  }).toList(),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxLarge),

            /// PRODUCT GRID - sabit kart oranları için GridView
            _isFiltering
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xxLarge),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xxLarge),
                          child: Text(
                            'No products found in this category',
                            style: AppTextStyles.bodySecondary,
                          ),
                        ),
                      )
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSpacing.xLarge,
                          mainAxisSpacing: AppSpacing.xLarge,
                          // Genişlik / yükseklik oranı; kartları biraz daha alçalt
                          childAspectRatio: 0.6,
                        ),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                return ProductCard(
                  key: ValueKey('product_${product.id}_${product.isLiked}_${product.averageRating}'), // Like ve rating durumu değiştiğinde widget'ı yenile
                  productId: product.id,
                  imageUrl: product.imageURL,
                  title: product.name,
                  category: product.tag.name,
                  rating: product.averageRating ?? 0.0, // Backend'den gelen rating
                  desc: product.description ?? '', // Use description from backend or empty string
                  isFavorite: product.isLiked ?? false, // Backend'den gelen like durumu
                  onTap: () async {
                    // ReviewPage'e git ve dönüşte güncellenmiş product'ı al
                    final updatedProduct = await Navigator.push<ProductDto>(
                      context,
                      SlideRightRoute(
                        page: ReviewPage(product: product),
                      ),
                    );
                    // ReviewPage'den dönen güncellenmiş product varsa, listeyi güncelle
                    if (updatedProduct != null) {
                      final allIndex = _allProducts.indexWhere((p) => p.id == updatedProduct.id);
                      final filteredIndex = _filteredProducts.indexWhere((p) => p.id == updatedProduct.id);
                      
                      if (allIndex != -1) {
                        setState(() {
                          _allProducts[allIndex] = updatedProduct;
                          // Eğer filtrelenmiş listede de varsa güncelle
                          if (filteredIndex != -1) {
                            _filteredProducts[filteredIndex] = updatedProduct;
                          }
                        });
                      }
                    } else {
                      // Eğer product dönmediyse, backend'den yeniden çek
                      await _refreshProductLikeStatus(product.id);
                    }
                  },
                  onFavoriteTap: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please login to like products'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }
                    
                    // Optimistic update - UI'ı hemen güncelle
                    final allIndex = _allProducts.indexWhere((p) => p.id == product.id);
                    final filteredIndex = _filteredProducts.indexWhere((p) => p.id == product.id);
                    
                    if (allIndex != -1) {
                      final currentLikeStatus = _allProducts[allIndex].isLiked ?? false;
                      setState(() {
                        _allProducts[allIndex] = _allProducts[allIndex].copyWith(
                          isLiked: !currentLikeStatus,
                        );
                        // Eğer filtrelenmiş listede de varsa güncelle
                        if (filteredIndex != -1) {
                          _filteredProducts[filteredIndex] = _filteredProducts[filteredIndex].copyWith(
                            isLiked: !currentLikeStatus,
                          );
                        }
                      });
                    }
                    
                    try {
                      // Token al (session zaten var, sadece token'ı header'a ekle)
                      final token = await _sessionHelper.getTokenAndSetHeader();
                      if (token == null) {
                        throw Exception('Failed to get Firebase ID token');
                      }
                      
                      // Backend'e like toggle isteği gönder
                      final newLikeStatus = await _interactionRepository.toggleProductLike(
                        token,
                        product.id,
                      );
                      
                      if (kDebugMode) {
                        debugPrint('HomePage - Like toggled: Product ${product.id}, New status: $newLikeStatus');
                      }
                      
                      // Backend'den gelen gerçek durumu güncelle (sadece like durumu için)
                      if (allIndex != -1) {
                        setState(() {
                          _allProducts[allIndex] = _allProducts[allIndex].copyWith(
                            isLiked: newLikeStatus,
                          );
                          // Eğer filtrelenmiş listede de varsa güncelle
                          if (filteredIndex != -1) {
                            _filteredProducts[filteredIndex] = _filteredProducts[filteredIndex].copyWith(
                              isLiked: newLikeStatus,
                            );
                          }
                        });
                      }
                    } catch (e) {
                      // Hata durumunda optimistic update'i geri al
                      if (allIndex != -1) {
                        setState(() {
                          _allProducts[allIndex] = _allProducts[allIndex].copyWith(
                            isLiked: product.isLiked,
                          );
                          // Eğer filtrelenmiş listede de varsa güncelle
                          if (filteredIndex != -1) {
                            _filteredProducts[filteredIndex] = _filteredProducts[filteredIndex].copyWith(
                              isLiked: product.isLiked,
                            );
                          }
                        });
                      }
                      
                      if (mounted) {
                        final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
                        ScaffoldMessenger.of(context).showSnackBar(
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
          ],
        ),
      ),
      ),
      /// BOTTOM NAV
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        onTap: (index) {
          if (index == 4) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProfilePage(),
              ),
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
      ),
    );
  }
}

/// CATEGORY CHIP
class _CategoryChip extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback? onTap;

  const _CategoryChip({
    required this.title,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.large),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
          alignment: Alignment.center,
          decoration: AppChipStyles.categoryChipDecoration(selected: selected),
          child: Text(
            title,
            style: AppChipStyles.categoryChipText(selected: selected),
          ),
        ),
      ),
    );
  }
}

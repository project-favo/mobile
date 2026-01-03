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
  int _selectedCategoryIndex = 0; // Seçili kategori index'i
  final TagRepository _tagRepository = TagRepository();
  final ProductRepository _productRepository = ProductRepository();
  final InteractionRepository _interactionRepository = InteractionRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  
  List<TagDto> _tags = [];
  List<ProductDto> _products = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
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
      final index = _products.indexWhere((p) => p.id == productId);
      if (index != -1) {
        setState(() {
          _products[index] = updatedProduct;
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
        _products = products;
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
    if (_isLoading && _products.isEmpty) {
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

    /// TOP 10 PRODUCTS - Use first 10 products from backend
    final top10Products = _products.take(10).toList();

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
                children: _tags.asMap().entries.map<Widget>((entry) {
                  final index = entry.key;
                  final tag = entry.value;
                  return _CategoryChip(
                    title: tag.name,
                    selected: index == _selectedCategoryIndex,
                    onTap: () {
                      setState(() {
                        _selectedCategoryIndex = index;
                      });
                      // TODO: Kategoriye göre ürünleri filtrele
                    },
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: AppSpacing.xxLarge),

            /// PRODUCT GRID - sabit kart oranları için GridView
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.xLarge,
                mainAxisSpacing: AppSpacing.xLarge,
                // Genişlik / yükseklik oranı; kartları biraz daha alçalt
                childAspectRatio: 0.6,
              ),
              itemCount: _products.length,
              itemBuilder: (context, index) {
                final product = _products[index];
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
                    // ReviewPage'e git ve dönüşte product'ın like durumunu kontrol et
                    await Navigator.push(
                      context,
                      SlideRightRoute(
                        page: ReviewPage(product: product),
                      ),
                    );
                    // ReviewPage'den dönüldüğünde product'ın like durumunu yenile
                    await _refreshProductLikeStatus(product.id);
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
                    final currentIndex = _products.indexWhere((p) => p.id == product.id);
                    if (currentIndex != -1) {
                      final currentLikeStatus = _products[currentIndex].isLiked ?? false;
                      setState(() {
                        _products[currentIndex] = _products[currentIndex].copyWith(
                          isLiked: !currentLikeStatus,
                        );
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
                      if (currentIndex != -1) {
                        setState(() {
                          _products[currentIndex] = _products[currentIndex].copyWith(
                            isLiked: newLikeStatus,
                          );
                        });
                      }
                    } catch (e) {
                      // Hata durumunda optimistic update'i geri al
                      if (currentIndex != -1) {
                        setState(() {
                          _products[currentIndex] = _products[currentIndex].copyWith(
                            isLiked: product.isLiked,
                          );
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

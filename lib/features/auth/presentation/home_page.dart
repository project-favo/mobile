import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_chip_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../widgets/product_card.dart';
import '../widgets/top_product_card.dart';
import 'profile/pages/profile_page.dart';
import 'review/pages/review_page.dart';
import '../data/repositories/tag_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/auth_repository.dart';
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
  final AuthRepository _authRepository = AuthRepository();
  
  List<TagDto> _tags = [];
  List<ProductDto> _products = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
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


      final firebaseIdToken = await user.getIdToken();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // IMPORTANT: Backend requires a session to be established via /api/auth/login
      // before making authenticated requests. This establishes the session on the backend.
      // Even though the user is already logged in via Firebase, we need to call the backend
      // login endpoint to establish the session for subsequent authenticated requests.
      try {
        await _authRepository.login(firebaseIdToken);
      } catch (e) {
        // If login fails, it might be because the user is already logged in
        // or the session expired. We'll continue and try the tag request anyway.
        // The backend might handle this gracefully.
      }

      // Fetch tags (requires authentication) and products (no auth required)
      final tags = await _tagRepository.getRootTags(firebaseIdToken);
      final products = await _productRepository.getAllProducts();
      
      setState(() {
        _tags = tags;
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'FAVO',
            style: AppTextStyles.HomeHeader,
          ),
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'FAVO',
            style: AppTextStyles.HomeHeader,
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Error: $_errorMessage',
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.large),
              ElevatedButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
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
        title: const Text(
          'FAVO',
          style: AppTextStyles.HomeHeader,
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
      body: SingleChildScrollView(
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
              // Top 10 kartları için yükseklik (kart + gölge)
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: top10Products.length,
                separatorBuilder: (_, __) =>
                const SizedBox(width: AppSpacing.xLarge),
                itemBuilder: (context, index) {
                  final product = top10Products[index];
                  return TopProductList(
                    imageUrl: product.imageURL,
                    title: product.name,
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
                  imageUrl: product.imageURL,
                  title: product.name,
                  category: product.tag.name,
                  rating: 0.0, // Default rating if not provided by backend
                  desc: product.description ?? '', // Use description from backend or empty string
                  isFavorite: false,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReviewPage(product: product),
                      ),
                    );
                  },// Default favorite status if not provided by backend
                );
              },
            ),
          ],
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

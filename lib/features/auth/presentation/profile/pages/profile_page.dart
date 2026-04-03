import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../auth/data/services/auth_service.dart';
import '../../../../auth/data/models/user_response_dto.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../widgets/product_card.dart';
import '../../home_page.dart';
import '../../search_page.dart';
import '../../review/pages/review_page.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/utils/resolve_media_url.dart';
import 'settings_page.dart';
import 'follow_list_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AuthService _authService = AuthService();
  final InteractionRepository _interactionRepository = InteractionRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  UserResponseDto? _user;
  bool _isLoading = true;
  String? _errorMessage;
  List<ProductDto> _wishlistProducts = [];
  List<ProductDto> _wishlistProductsOriginalOrder = [];
  bool _isLoadingWishlist = false;
  String? _wishlistError;
  List<ReviewDto> _myReviews = [];
  bool _isLoadingMyReviews = false;
  String? _myReviewsError;
  String _selectedDateSort = 'Newest';
  int _followerCount = 0;
  int _followingCount = 0;

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
      currentIndex: 4,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      onTap: (index) {
        if (index == 4) return;
        // 0: Add (+) → şimdilik hiçbir yere gitme / placeholder
        if (index == 0) return;
        if (index == 1) {
          Navigator.pushReplacement(context, _noAnimationRoute(const SearchPage()));
          return;
        }
        if (index == 2) {
          Navigator.pushReplacement(context, _noAnimationRoute(const HomePage()));
          return;
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.add),
          label: 'Add',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
        BottomNavigationBarItem(
          icon: Icon(
            Icons.home,
            size: 32,
          ),
          label: 'Home',
        ),
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
    _tabController = TabController(length: 2, vsync: this);
    _loadUserData();
    // Profil açılır açılmaz My Reviews'ı yükle (ilk sekme)
    _loadMyReviews();
    _tabController.addListener(() {
      if (_tabController.index == 1 && _wishlistProducts.isEmpty && !_isLoadingWishlist) {
        _loadWishlist();
      }
      setState(() {});
    });
  }

  Future<void> _loadMyReviews() async {
    setState(() {
      _isLoadingMyReviews = true;
      _myReviewsError = null;
    });

    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Please log in to see your reviews.');
      }

      final reviews = await _reviewRepository.getMyReviews(token);
      if (mounted) {
        setState(() {
          _myReviews = reviews;
          _isLoadingMyReviews = false;
        });
        _sortMyReviews();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _myReviewsError = ErrorHandler.getUserFriendlyMessage(e);
          _isLoadingMyReviews = false;
        });
      }
    }
  }

  Widget _buildMyReviewsTab() {
    if (_isLoadingMyReviews) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_myReviewsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _myReviewsError!,
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.large),
              TextButton(
                onPressed: _loadMyReviews,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_myReviews.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xLarge),
          child: Text(
            'Henüz yorum yok',
            style: AppTextStyles.bodySecondary,
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
      itemCount: _myReviews.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.medium),
      itemBuilder: (context, index) {
        final review = _myReviews[index];
        return InkWell(
          onTap: () {
            // Sayfa hemen açılsın; ürün ReviewPage içinde yüklenecek
            Navigator.push(
              context,
              SlideRightRoute(
                page: ReviewPage(
                  productId: review.productId,
                  productName: review.productName,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.large),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.productName,
                  style: AppTextStyles.heading3,
                ),
                const SizedBox(height: AppSpacing.small),
                Text(
                  review.title,
                  style: AppTextStyles.bodyMedium,
                ),
                if (review.description != null && review.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    review.description!,
                    style: AppTextStyles.bodySecondary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: AppSpacing.small),
                Row(
                  children: [
                    Icon(Icons.star, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${review.rating} / 5',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _authService.getMe();
      setState(() {
        _user = user;
        _isLoading = false;
      });
      _loadFollowCounts(user.id);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFollowCounts(String userId) async {
    final results = await Future.wait([
      _interactionRepository.getFollowerCount(userId),
      _interactionRepository.getFollowingCount(userId),
    ]);
    if (!mounted) return;
    setState(() {
      _followerCount = results[0];
      _followingCount = results[1];
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadWishlist() async {
    setState(() {
      _isLoadingWishlist = true;
      _wishlistError = null;
    });

    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      final products = await _interactionRepository.getMyWishlist(token);
      if (!mounted) return;
      setState(() {
        _wishlistProducts = List.from(products);
        _wishlistProductsOriginalOrder = List.from(products);
        _isLoadingWishlist = false;
      });
      _sortWishlist();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wishlistError = ErrorHandler.getUserFriendlyMessage(e);
        _isLoadingWishlist = false;
      });
    }
  }

  Widget _buildWishlistTab() {
    if (_isLoadingWishlist) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_wishlistError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Text(
            _wishlistError!,
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_wishlistProducts.isEmpty) {
      return const Center(
        child: Text(
          'Your wishlist is empty.',
          style: AppTextStyles.bodySecondary,
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
      itemCount: _wishlistProducts.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.large),
      itemBuilder: (context, index) {
        final product = _wishlistProducts[index];
        return ProductCard(
          productId: product.id,
          imageUrl: product.imageURL,
          title: product.name,
          category: product.tag.name,
          rating: product.averageRating ?? 0.0,
          desc: product.description ?? '',
          isFavorite: product.isLiked ?? true,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReviewPage(product: product),
              ),
            );
          },
          onFavoriteTap: () => _toggleWishlistLike(product),
        );
      },
    );
  }

  Future<void> _toggleWishlistLike(ProductDto product) async {
    final index = _wishlistProducts.indexWhere((p) => p.id == product.id);
    if (index == -1) return;

    final previous = _wishlistProducts[index];

    // Optimistic update
    setState(() {
      _wishlistProducts[index] = previous.copyWith(
        isLiked: !(previous.isLiked ?? true),
      );
    });

    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      final liked = await _interactionRepository.toggleProductLike(token, product.id);

      setState(() {
        if (!liked) {
          _wishlistProducts.removeWhere((p) => p.id == product.id);
          _wishlistProductsOriginalOrder.removeWhere((p) => p.id == product.id);
        } else {
          // Hâlâ likelıysa durumu güncelle
          final idx = _wishlistProducts.indexWhere((p) => p.id == product.id);
          if (idx != -1) {
            _wishlistProducts[idx] = _wishlistProducts[idx].copyWith(isLiked: liked);
          }
        }
      });
    } catch (e) {
      // Hata durumunda önceki haline dön
      setState(() {
        final idx = _wishlistProducts.indexWhere((p) => p.id == previous.id);
        if (idx != -1) {
          _wishlistProducts[idx] = previous;
        }
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

  void _sortWishlist() {
    if (_wishlistProducts.isEmpty) return;

    final hasAnyDate = _wishlistProducts.any((p) => p.createdAt != null);
    if (hasAnyDate) {
      final sorted = List<ProductDto>.from(_wishlistProducts);
      sorted.sort((a, b) {
        final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (_selectedDateSort == 'Newest') {
          return db.compareTo(da);
        }
        return da.compareTo(db);
      });
      _wishlistProducts = sorted;
    } else {
      if (_selectedDateSort == 'Newest') {
        _wishlistProducts = List.from(_wishlistProductsOriginalOrder);
      } else {
        _wishlistProducts = _wishlistProductsOriginalOrder.reversed.toList();
      }
    }
    setState(() {});
  }

  void _sortMyReviews() {
    if (_myReviews.isEmpty) return;
    final sorted = List<ReviewDto>.from(_myReviews);
    sorted.sort((a, b) {
      final da = DateTime.tryParse(a.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(b.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (_selectedDateSort == 'Newest') {
        return db.compareTo(da);
      }
      return da.compareTo(db);
    });
    _myReviews = sorted;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
    return Scaffold(
        backgroundColor: AppColors.background,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Profile',
            style: AppTextStyles.HomeHeader,
          ),
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    if (_errorMessage != null || _user == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Profile',
            style: AppTextStyles.HomeHeader,
          ),
        centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage ?? 'Failed to load user data',
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.large),
              ElevatedButton(
                onPressed: _loadUserData,
                child: const Text('Retry'),
              ),
            ],
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
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: AppTextStyles.HomeHeader,
          ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
                color: AppColors.primary,
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsPage(),
                ),
              );
              if (result == true || mounted) {
                _loadUserData();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xxLarge),
            ProfileAvatar(
              radius: 50,
              imageUrl: _user!.profileImageUrl,
              memoryBytes: decodeProfilePhotoBytes(_user!.profilePhotoData),
              fallbackInitial: _user!.userName,
            ),
            const SizedBox(height: AppSpacing.large),
            if (_user!.name != null || _user!.surname != null) ...[
              Text(
                '${_user!.name ?? ''} ${_user!.surname ?? ''}'.trim(),
                style: AppTextStyles.titleMedium,
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                '@${_user!.userName.toLowerCase().replaceAll(' ', '')}',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
            ] else ...[
              Text(
                '@${_user!.userName.toLowerCase().replaceAll(' ', '')}',
                style: AppTextStyles.titleMedium,
              ),
            ],
            const SizedBox(height: AppSpacing.xxLarge),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    SlideRightRoute(
                      page: FollowListPage(
                        userId: _user!.id,
                        title: 'Takipçiler',
                        isFollowers: true,
                      ),
                    ),
                  ),
                  child: _StatItem(count: _followerCount, label: 'Takipçi'),
                ),
                const SizedBox(width: AppSpacing.xxLarge),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    SlideRightRoute(
                      page: FollowListPage(
                        userId: _user!.id,
                        title: 'Takip Edilenler',
                        isFollowers: false,
                      ),
                    ),
                  ),
                  child: _StatItem(count: _followingCount, label: 'Takip'),
                ),
                const SizedBox(width: AppSpacing.xxLarge),
                _StatItem(count: _myReviews.length, label: 'Yorum'),
              ],
            ),
            const SizedBox(height: AppSpacing.xxLarge),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCard(title: 'AVERAGE RATING', content: '4.2 /5.0'),
                  ),
                  const SizedBox(width: AppSpacing.xLarge),
                  Expanded(
                    child: _SummaryCard(
                      title: 'TOP CATEGORY',
                      content: 'Electronics 35%\nBeauty 30%\nFashion 20%',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxLarge),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              tabs: const [
                Tab(text: 'My Reviews'),
                Tab(text: 'Wishlist'),
              ],
            ),
            const SizedBox(height: AppSpacing.large),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SORT BY DATE',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                  _SortDropdown(
                    label: 'Date',
                    items: const ['Newest', 'Oldest'],
                    value: _selectedDateSort,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedDateSort = value);
                      if (_tabController.index == 0) {
                        _sortMyReviews();
                      } else {
                        _sortWishlist();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxLarge),
            if (_tabController.index == 0)
              _buildMyReviewsTab()
            else
              _buildWishlistTab(),
            const SizedBox(height: AppSpacing.xxLarge),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;

  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: AppTextStyles.heading3,
        ),
        const SizedBox(height: AppSpacing.small),
        Text(label, style: AppTextStyles.bodySecondary),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String content;

  const _SummaryCard({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xLarge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.bodySecondary.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.medium),
          Text(
            content,
            style: AppTextStyles.heading3,
          ),
        ],
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final String label;
  final List<String> items;
  final String value;
  final ValueChanged<String?> onChanged;

  const _SortDropdown({
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      underline: Container(),
      style: AppTextStyles.bodyMedium,
      items: items.map((String item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(item),
        );
      }).toList(),
      onChanged: onChanged,
      icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
    );
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../../core/cache/product_memory_cache.dart';
import '../../../../../core/widgets/main_bottom_nav_items.dart';
import '../../../../../features/activity/presentation/activity_page.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../auth/data/services/auth_service.dart';
import '../../../../auth/data/models/user_response_dto.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/tag_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../widgets/product_card.dart';
import '../../home_page.dart';
import '../../search_page.dart';
import '../../review/pages/review_detail_page.dart';
import '../../review/pages/review_page.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/utils/resolve_media_url.dart';
import '../../../../../routes/app_routes.dart';
import '../../complete_app_profile_page.dart';
import 'settings_page.dart';
import 'follow_list_page.dart';
import '../widgets/profile_review_row_card.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AuthService _authService = AuthService();
  final InteractionRepository _interactionRepository = InteractionRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  final ProductRepository _productRepository = ProductRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  UserResponseDto? _user;
  bool _isLoading = true;
  String? _errorMessage;
  List<ProductDto> _wishlistProducts = [];
  List<ProductDto> _wishlistProductsOriginalOrder = [];
  bool _isLoadingWishlist = false;
  String? _wishlistError;
  List<ReviewDto> _myReviews = [];

  /// My Reviews satırlarında ürün görseli için (prefetch).
  final Map<String, ProductDto> _reviewProductHints = {};
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
        if (index == 1) return;
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            _noAnimationRoute(const SearchPage()),
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
      },
      items: MainBottomNavItems.barItems,
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
      if (_tabController.index == 1 &&
          _wishlistProducts.isEmpty &&
          !_isLoadingWishlist) {
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
          _reviewProductHints.clear();
        });
        _sortMyReviews();
        unawaited(_prefetchProductsForReviews(reviews));
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

  Future<void> _prefetchProductsForReviews(List<ReviewDto> reviews) async {
    final ids =
        reviews.map((r) => r.productId).where((s) => s.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    final token = await _sessionHelper.getTokenAndSetHeader();
    final list = ids.toList();
    const batch = 5;
    for (var i = 0; i < list.length; i += batch) {
      if (!mounted) return;
      final end = (i + batch > list.length) ? list.length : i + batch;
      final slice = list.sublist(i, end);
      await Future.wait(
        slice.map((id) async {
          try {
            final p = await _productRepository.getProductById(
              id,
              firebaseIdToken: token,
            );
            if (mounted) {
              setState(() => _reviewProductHints[id] = p);
            }
          } catch (_) {}
        }),
      );
    }
  }

  String _myReviewsAverageLabel() {
    if (_myReviews.isEmpty) return '—';
    final sum = _myReviews.fold<double>(0, (a, r) => a + r.rating);
    return (sum / _myReviews.length).toStringAsFixed(1);
  }

  ProductDto _productForReviewDetail(ReviewDto review, ProductDto? hint) {
    if (hint != null) return hint;
    return ProductDto(
      id: review.productId,
      name: review.productName,
      imageURL: '',
      description: null,
      tag: TagDto(id: '', name: ''),
    );
  }

  Widget _buildMyReviewsTab() {
    if (_isLoadingMyReviews) {
      return Column(
        children: [
          const ReviewCardSkeleton(),
          const SizedBox(height: AppSpacing.medium),
          const ReviewCardSkeleton(),
          const SizedBox(height: AppSpacing.medium),
          const ReviewCardSkeleton(),
        ],
      );
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
              TextButton(onPressed: _loadMyReviews, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_myReviews.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xLarge),
          child: Text('Henüz yorum yok', style: AppTextStyles.bodySecondary),
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
        final hint = _reviewProductHints[review.productId];
        return ProfileReviewRowCard(
          review: review,
          productImageUrl: hint?.imageURL,
          onTap: () {
            final cached =
                ProductMemoryCache.instance.peek(review.productId) ??
                _reviewProductHints[review.productId];
            final product = _productForReviewDetail(review, cached);
            Navigator.push(
              context,
              SlideRightRoute(
                page: ReviewDetailPage(
                  review: review,
                  product: product,
                ),
              ),
            );
          },
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
      await _authService.syncFirebaseUserAndRefreshIdToken();
      var user = await _authService.getMe();
      if (!user.hasProfileAvatarVisual && user.id.isNotEmpty) {
        final extra = await _authService.getUserById(user.id);
        user = user.withFilledAvatarFrom(extra);
      }
      setState(() {
        _user = user;
        _isLoading = false;
        if (user.id.isEmpty) {
          _followerCount = 0;
          _followingCount = 0;
        }
      });
      if (user.id.isNotEmpty) {
        unawaited(_loadFollowCounts(user.id));
      }
    } catch (e) {
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _signOutFromIncompleteProfile() async {
    AuthService.clearRegisterFormDraft();
    _sessionHelper.clearSession();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
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
      for (final p in products) {
        ProductMemoryCache.instance.remember(p);
      }
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
      return Column(
        children: [
          const ProductCardSkeleton(),
          const SizedBox(height: AppSpacing.large),
          const ProductCardSkeleton(),
        ],
      );
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
              MaterialPageRoute(builder: (_) => ReviewPage(product: product)),
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

      final liked = await _interactionRepository.toggleProductLike(
        token,
        product.id,
      );

      setState(() {
        if (!liked) {
          _wishlistProducts.removeWhere((p) => p.id == product.id);
          _wishlistProductsOriginalOrder.removeWhere((p) => p.id == product.id);
        } else {
          // Hâlâ likelıysa durumu güncelle
          final idx = _wishlistProducts.indexWhere((p) => p.id == product.id);
          if (idx != -1) {
            _wishlistProducts[idx] = _wishlistProducts[idx].copyWith(
              isLiked: liked,
            );
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
      final da =
          DateTime.tryParse(a.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db =
          DateTime.tryParse(b.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
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
          title: const Text('Profile', style: AppTextStyles.HomeHeader),
          centerTitle: true,
        ),
        body: const _ProfilePageSkeleton(),
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
          title: const Text('Profile', style: AppTextStyles.HomeHeader),
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

    if (_user != null && _user!.id.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Profile', style: AppTextStyles.HomeHeader),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxLarge),
                Icon(
                  Icons.verified_user_outlined,
                  size: 56,
                  color: AppColors.primary.withValues(alpha: 0.85),
                ),
                const SizedBox(height: AppSpacing.xLarge),
                Text(
                  'Profilinizi tamamlayın',
                  style: AppTextStyles.heading2.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.medium),
                Text(
                  'Kayıt ekranında yazdığınız bilgiler kayıtlıysa “Profili tamamla” '
                  'sayfasında otomatik dolar. Sunucu bazen kullanıcı kimliğini geç '
                  'gösterir; yine de bu adımı bir kez tamamlamanız gerekebilir.',
                  style: AppTextStyles.bodySecondary,
                  textAlign: TextAlign.center,
                ),
                if (_user!.email.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.large),
                  Text(
                    _user!.email,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (!(_user!.isEmailVerified)) ...[
                  const SizedBox(height: AppSpacing.medium),
                  Text(
                    'Email verification pending. Open the link in your inbox.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
                AppButton(
                  text: 'Profili tamamla',
                  onPressed: () async {
                    final ok = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CompleteAppProfilePage(),
                      ),
                    );
                    if (ok == true && mounted) {
                      await _loadUserData();
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                TextButton(
                  onPressed: _signOutFromIncompleteProfile,
                  child: Text(
                    'Çıkış yap',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxLarge),
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
        automaticallyImplyLeading: false,
        title: const Text('Profile', style: AppTextStyles.HomeHeader),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            color: AppColors.primary,
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
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
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ] else ...[
              Text(
                '@${_user!.userName.toLowerCase().replaceAll(' ', '')}',
                style: AppTextStyles.titleMedium,
              ),
            ],
            const SizedBox(height: AppSpacing.xxLarge),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.medium,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          () => Navigator.push(
                            context,
                            SlideRightRoute(
                              page: FollowListPage(
                                userId: _user!.id,
                                title: 'Followers',
                                isFollowers: true,
                              ),
                            ),
                          ),
                      child: _StatItem(
                        count: _followerCount,
                        label: 'Followers',
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          () => Navigator.push(
                            context,
                            SlideRightRoute(
                              page: FollowListPage(
                                userId: _user!.id,
                                title: 'Following',
                                isFollowers: false,
                              ),
                            ),
                          ),
                      child: _StatItem(
                        count: _followingCount,
                        label: 'Following',
                      ),
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      count: _myReviews.length,
                      label: 'Reviews',
                    ),
                  ),
                  Expanded(
                    child: Tooltip(
                      message:
                          'Yorumlarınızdaki yıldız ortalaması (5 üzerinden)',
                      child: _StatTextItem(
                        value: _myReviewsAverageLabel(),
                        label: 'Review avg',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxLarge),
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                tabs: const [Tab(text: 'My Reviews'), Tab(text: 'Wishlist')],
              ),
            ),
            const SizedBox(height: AppSpacing.large),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xLarge,
              ),
              child: Row(
                children: [
                  Text(
                    'Sort by date',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  _SortDropdown(
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

/// Ana profil verisi yüklenirken gerçek düzenle uyumlu shimmer.
class _ProfilePageSkeleton extends StatelessWidget {
  const _ProfilePageSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xxLarge),
          ClipOval(
            child: SkeletonLoader(
              width: 100,
              height: 100,
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          SkeletonLoader(
            width: 200,
            height: 22,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: AppSpacing.small),
          SkeletonLoader(
            width: 140,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: AppSpacing.xxLarge),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
            child: Row(
              children: [
                Expanded(child: _profileStatSkeleton()),
                Expanded(child: _profileStatSkeleton()),
                Expanded(child: _profileStatSkeleton()),
                Expanded(child: _profileStatSkeleton()),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxLarge),
          LayoutBuilder(
            builder: (context, c) {
              return SkeletonLoader(
                width: c.maxWidth,
                height: 46,
                borderRadius: BorderRadius.circular(14),
              );
            },
          ),
          const SizedBox(height: AppSpacing.large),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonLoader(
                  width: 100,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
                SkeletonLoader(
                  width: 88,
                  height: 32,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxLarge),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
            child: Column(
              children: [
                const ReviewCardSkeleton(),
                const SizedBox(height: AppSpacing.medium),
                const ReviewCardSkeleton(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxLarge),
        ],
      ),
    );
  }

  static Widget _profileStatSkeleton() {
    return Column(
      children: [
        SkeletonLoader(
          width: 36,
          height: 24,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: AppSpacing.small),
        SkeletonLoader(
          width: 64,
          height: 12,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
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
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.small),
        Text(
          label,
          style: AppTextStyles.bodySecondary,
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }
}

class _StatTextItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatTextItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: AppTextStyles.heading3, maxLines: 1),
        ),
        const SizedBox(height: AppSpacing.small),
        Text(
          label,
          style: AppTextStyles.bodySecondary,
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final List<String> items;
  final String value;
  final ValueChanged<String?> onChanged;

  const _SortDropdown({
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(10),
      iconSize: 20,
      style: AppTextStyles.bodySmall.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      items:
          items.map((String item) {
            return DropdownMenuItem<String>(value: item, child: Text(item));
          }).toList(),
      onChanged: onChanged,
      icon: const Icon(
        Icons.expand_more_rounded,
        size: 20,
        color: AppColors.textSecondary,
      ),
    );
  }
}

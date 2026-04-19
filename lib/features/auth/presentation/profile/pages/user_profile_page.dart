import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/utils/exceptions.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/cache/product_memory_cache.dart';
import '../../../../../core/utils/resolve_media_url.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../routes/app_routes.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/tag_dto.dart';
import '../../../data/models/conversation_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../messages/chat_detail_page.dart';
import '../../review/pages/review_detail_page.dart';
import 'follow_list_page.dart';
import '../widgets/profile_review_row_card.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;
  final String userName;
  final String? profileImageUrl;

  const UserProfilePage({
    super.key,
    required this.userId,
    required this.userName,
    this.profileImageUrl,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with SingleTickerProviderStateMixin {
  final InteractionRepository _interactionRepo = InteractionRepository();
  final ReviewRepository _reviewRepo = ReviewRepository();
  final ProductRepository _productRepository = ProductRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final AuthService _authService = AuthService();

  /// Reviews listesinde ürün görseli için prefetch.
  final Map<String, ProductDto> _reviewProductHints = {};

  late TabController _tabController;
  String _selectedDateSort = 'Newest';

  bool _isFollowing = false;
  bool _isFollowLoading = false;
  int _followerCount = 0;
  int _followingCount = 0;
  List<ReviewDto> _reviews = [];
  bool _isLoadingReviews = true;
  bool _isLoadingCounts = true;
  /// Görünen profil fotoğrafı (parametre veya yorum listesinden)
  String? _avatarImageUrl;
  Uint8List? _avatarMemoryBytes;
  String? _avatarPhotoDataRaw;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _avatarImageUrl = widget.profileImageUrl;
    _start();
  }

  /// Kendi kullanıcı kartına gidilmesin; deep link / hata durumunda kapat.
  Future<void> _start() async {
    try {
      final me = await _authService.getMe();
      if (!mounted) return;
      if (me.id.trim() == widget.userId.trim()) {
        Navigator.of(context).pop();
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    await _loadAll();
    if (mounted) await _enrichProfileFromApi();
  }

  Future<void> _enrichProfileFromApi() async {
    try {
      final u = await _authService.getUserById(widget.userId);
      if (u != null && mounted) {
        final bytes = decodeProfilePhotoBytes(u.profilePhotoData);
        setState(() {
          final url = u.profileImageUrl?.trim();
          if (url != null && url.isNotEmpty) _avatarImageUrl = url;
          if (bytes != null && bytes.isNotEmpty) _avatarMemoryBytes = bytes;
          if (u.profilePhotoData != null &&
              u.profilePhotoData!.trim().isNotEmpty) {
            _avatarPhotoDataRaw = u.profilePhotoData;
          }
        });
      }
    } catch (_) {}
    if (!mounted) return;
    final noUrl = _avatarImageUrl == null || _avatarImageUrl!.trim().isEmpty;
    final noMem =
        _avatarMemoryBytes == null || _avatarMemoryBytes!.isEmpty;
    if (noUrl && noMem) {
      for (final r in _reviews) {
        final u = r.ownerProfilePhotoUrl?.trim();
        if (u != null && u.isNotEmpty) {
          setState(() => _avatarImageUrl = u);
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final token = await _sessionHelper.ensureSession();
    await Future.wait([
      _loadCounts(),
      _loadIsFollowing(token),
      _loadReviews(token),
    ]);
  }

  Future<void> _loadCounts() async {
    final results = await Future.wait([
      _interactionRepo.getFollowerCount(widget.userId),
      _interactionRepo.getFollowingCount(widget.userId),
    ]);
    if (!mounted) return;
    setState(() {
      _followerCount = results[0];
      _followingCount = results[1];
      _isLoadingCounts = false;
    });
  }

  Future<void> _loadIsFollowing(String? token) async {
    final following = await _interactionRepo.isFollowing(token, widget.userId);
    if (!mounted) return;
    setState(() => _isFollowing = following);
  }

  Future<void> _loadReviews(String? token) async {
    try {
      final reviews = await _reviewRepo.getReviewsByUserId(
        widget.userId,
        firebaseIdToken: token,
      );
      if (!mounted) return;
      String? avatar = _avatarImageUrl;
      if (avatar == null || avatar.isEmpty) {
        for (final r in reviews) {
          final u = r.ownerProfilePhotoUrl?.trim();
          if (u != null && u.isNotEmpty) {
            avatar = u;
            break;
          }
        }
      }
      setState(() {
        _reviews = reviews;
        _reviewProductHints.clear();
        _avatarImageUrl = avatar;
        _isLoadingReviews = false;
      });
      _sortReviews();
      unawaited(_prefetchProductsForReviews(reviews));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingReviews = false);
    }
  }

  void _sortReviews() {
    if (_reviews.isEmpty) return;
    final sorted = List<ReviewDto>.from(_reviews);
    sorted.sort((a, b) {
      final da = DateTime.tryParse(a.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(b.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (_selectedDateSort == 'Newest') {
        return db.compareTo(da);
      }
      return da.compareTo(db);
    });
    setState(() => _reviews = sorted);
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

  String _reviewsAverageLabel() {
    if (_reviews.isEmpty) return '—';
    final sum = _reviews.fold<double>(0, (a, r) => a + r.rating);
    return (sum / _reviews.length).toStringAsFixed(1);
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

  Future<void> _toggleFollow() async {
    if (_isFollowLoading) return;
    setState(() => _isFollowLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Sign in to follow or unfollow users.');
      }
      final token = await user.getIdToken(true);
      if (token == null) {
        throw Exception('Sign in to follow or unfollow users.');
      }
      final nowFollowing = await _interactionRepo.toggleFollow(token, widget.userId);
      if (!mounted) return;
      setState(() {
        _isFollowing = nowFollowing;
        _followerCount += nowFollowing ? 1 : -1;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  void _openChat() {
    final recipientId = int.tryParse(widget.userId);
    if (recipientId == null) return;
    final syntheticConversation = ConversationDto(
      id: 0,
      otherParticipant: ConversationUserDto(
        id: recipientId,
        username: widget.userName,
        profilePhotoUrl: _avatarImageUrl ?? widget.profileImageUrl,
        profilePhotoData: _avatarPhotoDataRaw,
      ),
      lastMessage: '',
      lastMessageAt: '',
      unreadCount: 0,
    );
    Navigator.push(
      context,
      SlideRightRoute(
        page: ChatDetailPage(
          conversation: syntheticConversation,
          recipientId: recipientId,
        ),
      ),
    );
  }

  void _openFollowerList() {
    Navigator.push(
      context,
      SlideRightRoute(
        page: FollowListPage(
          userId: widget.userId,
          title: 'Followers',
          isFollowers: true,
        ),
      ),
    );
  }

  void _openFollowingList() {
    Navigator.push(
      context,
      SlideRightRoute(
        page: FollowListPage(
          userId: widget.userId,
          title: 'Following',
          isFollowers: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final handle =
        '@${widget.userName.toLowerCase().replaceAll(' ', '')}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: const Text(
          'Profile',
          style: AppTextStyles.HomeHeader,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            color: AppColors.primary,
            tooltip: 'Message',
            onPressed: _openChat,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xxLarge),
              ProfileAvatar(
                radius: 50,
                imageUrl: _avatarImageUrl ?? widget.profileImageUrl,
                memoryBytes: _avatarMemoryBytes,
                fallbackInitial: widget.userName,
              ),
              const SizedBox(height: AppSpacing.large),
              Text(
                widget.userName,
                style: AppTextStyles.titleMedium,
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                handle,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxLarge),
              _isLoadingCounts
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.medium,
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < 4; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.small,
                                ),
                                child: SkeletonLoader(
                                  width: double.infinity,
                                  height: 44,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.medium,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _openFollowerList,
                              child: _StatItem(
                                count: _followerCount,
                                label: 'Followers',
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: _openFollowingList,
                              child: _StatItem(
                                count: _followingCount,
                                label: 'Following',
                              ),
                            ),
                          ),
                          Expanded(
                            child: _StatItem(
                              count: _isLoadingReviews ? 0 : _reviews.length,
                              label: 'Reviews',
                            ),
                          ),
                          Expanded(
                            child: Tooltip(
                              message:
                                  'Bu kullanıcının yorumlarındaki yıldız ortalaması (5 üzerinden)',
                              child: _StatTextItem(
                                value: _reviewsAverageLabel(),
                                label: 'Review avg',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              const SizedBox(height: AppSpacing.large),
              SizedBox(
                width: 200,
                child: ElevatedButton(
                  onPressed: _isFollowLoading ? null : _toggleFollow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFollowing
                        ? AppColors.surface
                        : AppColors.primary,
                    foregroundColor:
                        _isFollowing ? AppColors.primary : Colors.white,
                    side: _isFollowing
                        ? const BorderSide(color: AppColors.primary)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.medium,
                    ),
                  ),
                  child: _isFollowLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Text(
                          _isFollowing ? 'Unfollow' : 'Follow',
                          style: AppTextStyles.button.copyWith(
                            color: _isFollowing
                                ? AppColors.primary
                                : Colors.white,
                          ),
                        ),
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
                  tabs: const [
                    Tab(text: 'Reviews'),
                  ],
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
                        _sortReviews();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.medium),
              if (_isLoadingReviews)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xLarge,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < 3; i++)
                        const Padding(
                          padding: EdgeInsets.only(bottom: AppSpacing.medium),
                          child: ReviewCardSkeleton(),
                        ),
                    ],
                  ),
                )
              else if (_reviews.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xLarge),
                  child: Center(
                    child: Text(
                      'No reviews yet.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xLarge,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _reviews.length; i++) ...[
                        if (i > 0)
                          const SizedBox(height: AppSpacing.medium),
                        ProfileReviewRowCard(
                          review: _reviews[i],
                          productImageUrl:
                              _reviewProductHints[_reviews[i].productId]
                                  ?.imageURL,
                          onTap: () {
                            final r = _reviews[i];
                            final cached =
                                ProductMemoryCache.instance.peek(r.productId) ??
                                _reviewProductHints[r.productId];
                            final product = _productForReviewDetail(r, cached);
                            Navigator.push(
                              context,
                              SlideRightRoute(
                                page: ReviewDetailPage(
                                  review: r,
                                  product: product,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.xxLarge),
            ],
          ),
        ),
      ),
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
      items: items.map((String item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(item),
        );
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

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/config/api_config.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/review_repository.dart';

class ReviewDetailPage extends StatefulWidget {
  final ReviewDto review;
  final ProductDto product;

  const ReviewDetailPage({
    super.key,
    required this.review,
    required this.product,
  });

  @override
  State<ReviewDetailPage> createState() => _ReviewDetailPageState();
}

class _ReviewDetailPageState extends State<ReviewDetailPage> {
  final InteractionRepository _interactionRepository = InteractionRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  late ReviewDto _currentReview;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentReview = widget.review;
    _refreshReview();
  }

  /// Review'ı backend'den yeniden yükler (like durumu için)
  Future<void> _refreshReview() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final firebaseIdToken = await user.getIdToken(true);
      if (firebaseIdToken == null) return;

      // Backend session'ı kur
      try {
        final authRepository = AuthRepository();
        await authRepository.login(firebaseIdToken);
      } catch (e) {
        print('Login error in refresh: $e');
      }

      // Review'ı tamamen yeniden yükle
      final updatedReview = await _reviewRepository.getReviewById(
        _currentReview.id,
        firebaseIdToken: firebaseIdToken,
      );

      setState(() {
        _currentReview = updatedReview;
      });
    } catch (e) {
      print('Failed to refresh review: $e');
    }
  }

  /// Media URL'ini oluşturur
  String _getMediaUrl(String mediaId) {
    return '${ApiConfig.baseUrl}/api/media/$mediaId';
  }

  /// Tarih formatını düzenler
  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  /// Username'den avatar initials oluşturur
  String _getInitials(String username) {
    if (username.isEmpty) return 'U';
    final parts = username.replaceAll('@', '').split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0].toUpperCase()}${parts[1][0].toUpperCase()}';
    }
    return username[0].toUpperCase();
  }

  Future<void> _toggleLike() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to like reviews'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final firebaseIdToken = await user.getIdToken(true);
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Backend session'ı yenile
      try {
        final authRepository = AuthRepository();
        await authRepository.login(firebaseIdToken);
      } catch (e) {
        print('Login error: $e');
      }

      await _interactionRepository.toggleReviewLike(
        firebaseIdToken,
        _currentReview.id,
      );

      // Review'ı backend'den tekrar çek
      await _refreshReview();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle like: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Review Details',
          style: AppTextStyles.heading2,
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xLarge),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              /// REVIEWER INFO
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      _getInitials(_currentReview.ownerUserName),
                      style: AppTextStyles.bodyBold.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.medium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '@${_currentReview.ownerUserName}',
                              style: AppTextStyles.bodyBold,
                            ),
                            if (_currentReview.isCollaborative) ...[
                              const SizedBox(width: AppSpacing.small),
                              Text(
                                'Sponsored',
                                style: AppTextStyles.chip.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentReview.isCollaborative
                              ? 'Sponsored - ${_formatDate(_currentReview.createdAt)}'
                              : 'Not Sponsored - ${_formatDate(_currentReview.createdAt)}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xLarge),

              /// RATING
              Row(
                children: [
                  ...List.generate(
                    5,
                    (index) => Icon(
                      Icons.star,
                      size: 24,
                      color: index < _currentReview.rating
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.small),
                  Text(
                    '${_currentReview.rating}.0',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xLarge),

              /// PRODUCT INFO
              Container(
                padding: const EdgeInsets.all(AppSpacing.large),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.product.imageURL,
                        width: 100,
                        height: 100,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 100,
                            height: 100,
                            color: AppColors.textSecondary.withOpacity(0.1),
                            child: const Icon(
                              Icons.image_not_supported,
                              color: AppColors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.medium),
                    // Product Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product.name,
                            style: AppTextStyles.bodyBold,
                          ),
                          if (widget.product.description != null &&
                              widget.product.description!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.product.description!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xLarge),

              /// REVIEW IMAGES (yukarıda)
              if (_currentReview.mediaList.isNotEmpty) ...[
                Text(
                  'Review Images',
                  style: AppTextStyles.heading3,
                ),
                const SizedBox(height: AppSpacing.medium),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _currentReview.mediaList.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppSpacing.medium),
                    itemBuilder: (context, index) {
                      final media = _currentReview.mediaList[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _getMediaUrl(media.id),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 120,
                              height: 120,
                              color: AppColors.textSecondary.withOpacity(0.1),
                              child: const Icon(
                                Icons.image_not_supported,
                                color: AppColors.textSecondary,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.xLarge),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.large),
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.textSecondary.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.image_outlined,
                        color: AppColors.textSecondary,
                        size: 24,
                      ),
                      const SizedBox(width: AppSpacing.medium),
                      Text(
                        'No images uploaded',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xLarge),
              ],

              /// REVIEW TEXT (fotoğrafların altında, büyük)
              Text(
                _currentReview.description ?? _currentReview.title,
                style: AppTextStyles.heading3,
              ),
                  ],
                ),
              ),
            ),
          ),
          /// LIKE / REPORT (en altta sabit)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xLarge,
              vertical: AppSpacing.large,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: _isLoading ? null : _toggleLike,
                  child: Row(
                    children: [
                      _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(AppColors.primary),
                              ),
                            )
                          : Icon(
                              _currentReview.isLikedByCurrentUser
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 24,
                              color: _currentReview.isLikedByCurrentUser
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                      if (_currentReview.likeCount > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          _currentReview.likeCount.toString(),
                          style: AppTextStyles.bodyBold,
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    // TODO: Report functionality
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report functionality coming soon'),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.flag_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    'Report',
                    style: AppTextStyles.body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


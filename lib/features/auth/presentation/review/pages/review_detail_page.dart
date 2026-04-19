import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/config/api_config.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/network/api_client.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/repositories/message_repository.dart';
import '../../../data/services/auth_service.dart';
import '../widgets/report_review_sheet.dart';

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
  final SessionHelper _sessionHelper = SessionHelper();
  final ApiClient _apiClient = ApiClient();
  late ReviewDto _currentReview;
  final MessageRepository _messageRepository = MessageRepository();

  /// Şikayet butonunu gizlemek için (kendi yorumu).
  String? _viewerUserId;

  @override
  void initState() {
    super.initState();
    _currentReview = widget.review;
    _refreshReview();
  }

  bool get _canShowChatIcon {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    // ownerId backend user id, elimizde birebir karşılığı yok; username ile basic kontrol yapıyoruz
    return _currentReview.ownerUserName.toLowerCase() !=
        (user.email ?? '').split('@').first.toLowerCase();
  }

  /// Review'ı backend'den yeniden yükler (like durumu için)
  Future<void> _refreshReview() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get token (session already exists via cookies)
      final firebaseIdToken = await _sessionHelper.getTokenAndSetHeader();
      if (firebaseIdToken == null) return;

      // Review'ı tamamen yeniden yükle
      final updatedReview = await _reviewRepository.getReviewById(
        _currentReview.id,
        firebaseIdToken: firebaseIdToken,
      );

      String? viewerId;
      try {
        viewerId = (await AuthService().getMe()).id;
      } catch (_) {}

      setState(() {
        _currentReview = updatedReview;
        _viewerUserId = viewerId;
      });
    } catch (_) {}
  }

  /// Media image'ı authentication header ile yükler ve Uint8List olarak döndürür
  /// Dio kullanarak cookie'lerin de gönderilmesini sağlar
  Future<Uint8List?> _loadMediaImage(String mediaUrl) async {
    try {
      // Token'ı al - ensureSession kullanarak güncel token'ı garanti et
      final firebaseIdToken = await _sessionHelper.ensureSession();
      
      if (firebaseIdToken == null) return null;

      _apiClient.setAuthToken(firebaseIdToken);

      // Media URL'den path'i çıkar (baseUrl zaten ApiClient'te var)
      final uri = Uri.parse(mediaUrl);
      String path = uri.path;
      if (uri.query.isNotEmpty) {
        path = '$path?${uri.query}';
      }

      // Dio ile binary response al
      final response = await _apiClient.dio.get(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Accept': 'image/*',
          },
        ),
      ).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200 && response.data != null) {
        final bytes = response.data as List<int>;
        return Uint8List.fromList(bytes);
      }
      return null;
    } on DioException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onChatIconTap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to send messages'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    final controller = TextEditingController();
    bool isSending = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.xLarge,
            right: AppSpacing.xLarge,
            top: AppSpacing.large,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.large,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              Future<void> send() async {
                final text = controller.text.trim();
                if (text.isEmpty || isSending) return;
                setState(() => isSending = true);
                try {
                  final token = await _sessionHelper.ensureSession();
                  if (token == null) {
                    throw Exception('Failed to get Firebase ID token');
                  }
                  await _messageRepository.sendMessage(
                    recipientId: int.tryParse(_currentReview.ownerId),
                    content: text,
                  );
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Message sent to @${_currentReview.ownerUserName}'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    final msg = ErrorHandler.getUserFriendlyMessage(e);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                  setState(() => isSending = false);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Message @${_currentReview.ownerUserName}',
                    style: AppTextStyles.heading3,
                  ),
                  const SizedBox(height: AppSpacing.medium),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: 'Write your message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.medium),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: isSending ? null : send,
                      child: isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Send'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
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
            content: Text('Please login to upvote reviews'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // Optimistic update - UI'ı hemen güncelle (loading indicator yok)
    final previousLikeStatus = _currentReview.isLikedByCurrentUser;
    final previousLikeCount = _currentReview.likeCount;
    
    setState(() {
      _currentReview = ReviewDto(
        id: _currentReview.id,
        title: _currentReview.title,
        description: _currentReview.description,
        isCollaborative: _currentReview.isCollaborative,
        rating: _currentReview.rating,
        createdAt: _currentReview.createdAt,
        productId: _currentReview.productId,
        productName: _currentReview.productName,
        ownerId: _currentReview.ownerId,
        ownerUserName: _currentReview.ownerUserName,
        mediaList: _currentReview.mediaList,
        likeCount: previousLikeStatus 
            ? (previousLikeCount > 0 ? previousLikeCount - 1 : 0)
            : previousLikeCount + 1,
        isLikedByCurrentUser: !previousLikeStatus,
      );
    });

    try {
      // Get token (session already exists via cookies)
      final firebaseIdToken = await _sessionHelper.getTokenAndSetHeader();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Upvote toggle yap
      final newLikeStatus = await _interactionRepository.toggleReviewLike(
        firebaseIdToken,
        _currentReview.id,
      );

      // Review'ı backend'den tekrar çek (güncel durum için)
      try {
        final updatedReview = await _reviewRepository.getReviewById(
          _currentReview.id,
          firebaseIdToken: firebaseIdToken,
        );
        
        setState(() {
          _currentReview = updatedReview;
        });
      } catch (e) {
        // Backend'den çekme başarısız olursa, toggle'dan dönen değeri kullan
        setState(() {
          _currentReview = ReviewDto(
            id: _currentReview.id,
            title: _currentReview.title,
            description: _currentReview.description,
            isCollaborative: _currentReview.isCollaborative,
            rating: _currentReview.rating,
            createdAt: _currentReview.createdAt,
            productId: _currentReview.productId,
            productName: _currentReview.productName,
            ownerId: _currentReview.ownerId,
            ownerUserName: _currentReview.ownerUserName,
            mediaList: _currentReview.mediaList,
            likeCount: newLikeStatus
                ? (previousLikeCount + 1)
                : (previousLikeCount > 0 ? previousLikeCount - 1 : 0),
            isLikedByCurrentUser: newLikeStatus,
          );
        });
      }
    } catch (e) {
      // Hata durumunda optimistic update'i geri al
      setState(() {
        _currentReview = ReviewDto(
          id: _currentReview.id,
          title: _currentReview.title,
          description: _currentReview.description,
          isCollaborative: _currentReview.isCollaborative,
          rating: _currentReview.rating,
          createdAt: _currentReview.createdAt,
          productId: _currentReview.productId,
          productName: _currentReview.productName,
          ownerId: _currentReview.ownerId,
          ownerUserName: _currentReview.ownerUserName,
          mediaList: _currentReview.mediaList,
          likeCount: previousLikeCount,
          isLikedByCurrentUser: previousLikeStatus,
        );
      });
      
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
          onPressed: () {
            // Review'da değişiklik olduysa (like/unlike) true döndür
            Navigator.pop(context, true);
          },
        ),
        title: const Text(
          'Review Details',
          style: AppTextStyles.heading2,
        ),
        centerTitle: false,
        actions: [
          if (_canShowChatIcon)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              color: AppColors.primary,
              onPressed: _onChatIconTap,
            ),
        ],
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
                      // Backend'den direkt URL geliyorsa onu kullan, yoksa id'den oluştur
                      final mediaUrl = media.getMediaUrl(ApiConfig.baseUrl);

                      // Eğer backend'den direkt URL geliyorsa, Image.network kullan
                      if (media.url != null && media.url!.isNotEmpty) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            media.url!,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: AppColors.textSecondary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.image_not_supported,
                                  color: AppColors.textSecondary,
                                ),
                              );
                            },
                          ),
                        );
                      }
                      
                      if (media.imageUrl != null && media.imageUrl!.isNotEmpty) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            media.imageUrl!,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: AppColors.textSecondary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.image_not_supported,
                                  color: AppColors.textSecondary,
                                ),
                              );
                            },
                          ),
                        );
                      }
                      
                      // Backend'den URL gelmiyorsa, authentication ile yükle
                      return FutureBuilder<Uint8List?>(
                        future: _loadMediaImage(mediaUrl),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: AppColors.textSecondary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            );
                          }
                          
                          if (snapshot.hasError || snapshot.data == null) {
                            return Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: AppColors.textSecondary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.image_not_supported,
                                color: AppColors.textSecondary,
                              ),
                            );
                          }
                          
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              snapshot.data!,
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
                  onTap: _toggleLike,
                  child: Row(
                    children: [
                      Icon(
                        _currentReview.isLikedByCurrentUser
                            ? Icons.thumb_up
                            : Icons.thumb_up_alt_outlined,
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
                if (_viewerUserId == null ||
                    _viewerUserId!.trim() !=
                        _currentReview.ownerId.trim())
                  TextButton.icon(
                    onPressed: () async {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Please sign in to report a review'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }
                      final ok = await showReportReviewSheet(
                        context,
                        reviewId: _currentReview.id,
                      );
                      if (mounted && ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Thanks — your report was sent'),
                          ),
                        );
                      }
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



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
import '../../../../../core/cache/current_user_cache.dart';
import '../../../../../core/cache/review_memory_cache.dart';
import '../../../../../core/utils/in_flight_id_lock.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import 'review_page.dart';
import '../../profile/pages/user_profile_page.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/repositories/message_repository.dart';
import '../../../data/services/auth_service.dart';
import '../widgets/report_review_sheet.dart';
import '../widgets/review_delete_flow.dart';

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

  /// Media futures cached by media ID — prevents FutureBuilder from restarting on every rebuild.
  final Map<String, Future<Uint8List?>> _mediaFutures = {};
  final InFlightFlag _reviewDetailLikeLock = InFlightFlag();
  final InFlightFlag _reviewDeleteLock = InFlightFlag();

  bool get _isOwnReview {
    if (CurrentUserCache.instance.isMyReview(_currentReview)) return true;
    return _viewerUserId != null &&
        _viewerUserId!.trim() == _currentReview.ownerId.trim();
  }

  @override
  void initState() {
    super.initState();
    _currentReview = widget.review;
    _initMediaFutures();
    final w = CurrentUserCache.instance;
    if (w.isMyReview(_currentReview)) {
      _viewerUserId = w.userId;
    }
    unawaited(_loadViewerId());
    // Defer the refresh so the first frame renders fully before making an API call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshReview();
    });
  }

  /// Pre-creates and caches a Future for each auth-required media item.
  /// Using putIfAbsent means existing futures survive rebuilds caused by _refreshReview.
  void _initMediaFutures() {
    for (final media in _currentReview.mediaList) {
      if ((media.url == null || media.url!.isEmpty) &&
          (media.imageUrl == null || media.imageUrl!.isEmpty)) {
        final mediaUrl = media.getMediaUrl(ApiConfig.baseUrl);
        _mediaFutures.putIfAbsent(media.id, () => _loadMediaImage(mediaUrl));
      }
    }
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

      String? viewerId = CurrentUserCache.instance.userId;
      try {
        viewerId = (await AuthService().getMe()).id;
      } catch (_) {}

      _initMediaFutures();
      setState(() {
        _currentReview = updatedReview;
        if (viewerId != null && viewerId.trim().isNotEmpty) {
          _viewerUserId = viewerId;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadViewerId() async {
    final c = CurrentUserCache.instance;
    if (c.isMyReview(_currentReview) && c.hasUserId) {
      if (!mounted) return;
      setState(() => _viewerUserId = c.userId);
      return;
    }
    try {
      final me = await AuthService().getMe();
      if (!mounted) return;
      setState(() => _viewerUserId = me.id);
    } catch (_) {}
  }

  Future<void> _onDeleteReview() async {
    if (!_reviewDeleteLock.tryEnter()) return;
    try {
      final ok = await ReviewDeleteFlow.confirmAndDelete(
        context,
        repository: _reviewRepository,
        sessionHelper: _sessionHelper,
        reviewId: _currentReview.id,
      );
      if (ok && mounted) {
        ReviewMemoryCache.instance.removeReviewFromProduct(
          _currentReview.productId,
          _currentReview.id,
        );
        Navigator.of(context).pop(ReviewDeleteFlow.popResultDeleted);
      }
    } finally {
      _reviewDeleteLock.leave();
    }
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

  void _openOwnerProfile() {
    if (_isOwnReview) {
      return;
    }
    Navigator.push(
      context,
      SlideRightRoute(
        page: UserProfilePage(
          userId: _currentReview.ownerId,
          userName: _currentReview.ownerUserName,
          profileImageUrl: _currentReview.ownerProfilePhotoUrl,
        ),
      ),
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

  void _openMediaPreview(String imageUrl) {
    if (imageUrl.trim().isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder:
          (ctx) => Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      panEnabled: true,
                      clipBehavior: Clip.none,
                      minScale: 1,
                      maxScale: 5,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (context, error, stackTrace) => Container(
                              width: 240,
                              height: 240,
                              color: AppColors.textSecondary.withOpacity(0.1),
                              child: const Icon(
                                Icons.image_not_supported,
                                size: 42,
                                color: AppColors.textSecondary,
                              ),
                            ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
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

    if (!_reviewDetailLikeLock.tryEnter()) return;

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

      // Toggle and confirm with actual server response
      final newLikeStatus = await _interactionRepository.toggleReviewLike(
        firebaseIdToken,
        _currentReview.id,
      );

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
    } finally {
      _reviewDetailLikeLock.leave();
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xLarge,
                  AppSpacing.xLarge,
                  AppSpacing.xLarge,
                  AppSpacing.xxLarge,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              /// REVIEWER INFO
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openOwnerProfile,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.large),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
                    ),
                    child: Row(
                      children: [
                        ProfileAvatarImage(
                          size: 48,
                          imageUrl: _currentReview.ownerProfilePhotoUrl,
                          fallbackInitial: _currentReview.ownerUserName,
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
                                    style: AppTextStyles.bodyBold.copyWith(fontSize: 17),
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
                                    ? 'Sponsored review · ${_formatDate(_currentReview.createdAt)}'
                                    : 'Verified review · ${_formatDate(_currentReview.createdAt)}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

              /// PRODUCT INFO (tam karta basınca ürün sayfası)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    final pid =
                        widget.product.id.trim().isNotEmpty
                            ? widget.product.id
                            : _currentReview.productId.trim();
                    if (pid.isEmpty) return;
                    final name =
                        widget.product.name.trim().isNotEmpty
                            ? widget.product.name
                            : _currentReview.productName;
                    Navigator.push(
                      context,
                      SlideRightRoute(
                        page: ReviewPage(
                          product:
                              widget.product.id.trim().isNotEmpty
                                  ? widget.product
                                  : null,
                          productId: pid,
                          productName: name,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.large),
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            widget.product.imageURL,
                            width: 100,
                            height: 100,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            gaplessPlayback: true,
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
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textSecondary.withOpacity(0.6),
                        ),
                      ],
                    ),
                  ),
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
                        return GestureDetector(
                          onTap: () => _openMediaPreview(media.url!),
                          child: ClipRRect(
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
                          ),
                        );
                      }
                      
                      if (media.imageUrl != null && media.imageUrl!.isNotEmpty) {
                        return GestureDetector(
                          onTap: () => _openMediaPreview(media.imageUrl!),
                          child: ClipRRect(
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
                          ),
                        );
                      }
                      
                      // Backend'den URL gelmiyorsa, authentication ile yükle
                      return FutureBuilder<Uint8List?>(
                        future: _mediaFutures[media.id] ??
                            (_mediaFutures[media.id] = _loadMediaImage(mediaUrl)),
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
                          
                          return GestureDetector(
                            onTap:
                                () => showDialog<void>(
                                  context: context,
                                  barrierColor: Colors.black87,
                                  builder:
                                      (ctx) => Scaffold(
                                        backgroundColor: Colors.transparent,
                                        body: SafeArea(
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: InteractiveViewer(
                                                  minScale: 1,
                                                  maxScale: 5,
                                                  child: Image.memory(
                                                    snapshot.data!,
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: IconButton(
                                                  onPressed:
                                                      () => Navigator.of(ctx).pop(),
                                                  icon: const Icon(
                                                    Icons.close,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                ),
                            child: ClipRRect(
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

              /// REVIEW TEXT
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.large),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
                ),
                child: Text(
                  _currentReview.description ?? _currentReview.title,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 16,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
                  ],
                ),
              ),
            ),
          ),
          /// BOTTOM ACTIONS
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(
              AppSpacing.xLarge,
              AppSpacing.small,
              AppSpacing.xLarge,
              AppSpacing.medium,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.medium,
                vertical: AppSpacing.small,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _toggleLike,
                    icon: Icon(
                      _currentReview.isLikedByCurrentUser
                          ? Icons.thumb_up
                          : Icons.thumb_up_alt_outlined,
                      size: 20,
                      color:
                          _currentReview.isLikedByCurrentUser
                              ? AppColors.primary
                              : AppColors.textSecondary,
                    ),
                    label: Text(
                      '${_currentReview.likeCount}',
                      style: AppTextStyles.body.copyWith(
                        color:
                            _currentReview.isLikedByCurrentUser
                                ? AppColors.primary
                                : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_canShowChatIcon)
                    TextButton.icon(
                      onPressed: _onChatIconTap,
                      icon: const Icon(
                        Icons.chat_bubble_outline,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      label: Text(
                        'Message',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (_isOwnReview)
                    OutlinedButton.icon(
                      onPressed: _onDeleteReview,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(
                          color: AppColors.border.withValues(alpha: 0.9),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      label: Text(
                        'Delete',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (!_isOwnReview)
                    TextButton.icon(
                      onPressed: () async {
                        await openReviewReportFlow(
                          context,
                          reviewId: _currentReview.id,
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
          ),
        ],
      ),
    );
  }
}



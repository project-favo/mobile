import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/review_card.dart';
import '../widgets/report_review_sheet.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/custom_refresh_indicator.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/product_rating_display.dart';
import '../../../../../core/widgets/new_product_badge.dart';
import '../../../../../core/cache/product_memory_cache.dart';
import '../../../../../core/cache/review_memory_cache.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/tag_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/message_repository.dart';
import '../../../data/services/auth_service.dart';
import 'add_review_page.dart';
import 'review_detail_page.dart';
import 'compare_product_select_page.dart';
import '../../messages/product_ai_chat_page.dart';
import '../../profile/pages/user_profile_page.dart';

class ReviewPage extends StatefulWidget {
  /// Tam product verilirse doğrudan kullanılır.
  /// Sadece [productId] (ve isteğe bağlı [productName]) verilirse sayfa hemen açılır, ürün arka planda yüklenir.
  final ProductDto? product;
  final String? productId;
  final String? productName;

  const ReviewPage({super.key, this.product, this.productId, this.productName});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final InteractionRepository _interactionRepository = InteractionRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  final ProductRepository _productRepository = ProductRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final MessageRepository _messageRepository = MessageRepository();
  String? _currentUsername;
  String? _currentUserId;
  late ProductDto _currentProduct;
  bool _isLoadingProduct =
      false; // productId ile açıldıysa ürün yüklenene kadar
  List<ReviewDto> _reviews = [];
  bool _isLoadingReviews = true;
  String? _errorMessage;
  int _likeCount = 0;
  bool _hasLoadedLikeCount = false;
  bool _isRatingExpanded = false;
  bool _isDescriptionExpanded = false;
  static const EdgeInsets _contentHorizontalPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xxLarge,
  );

  bool get _hasLoadedReviewSummary => !_isLoadingReviews && _hasLoadedLikeCount;

  String _formatReviewRelativeDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final now = DateTime.now();
    var diff = now.difference(parsed.toLocal());
    if (diff.isNegative) diff = Duration.zero;
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) {
      final m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 1) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 30) {
      final d = diff.inDays;
      return '$d day${d == 1 ? '' : 's'} ago';
    }
    final month = (diff.inDays / 30).floor();
    if (month < 12) return '$month month${month == 1 ? '' : 's'} ago';
    final year = (diff.inDays / 365).floor();
    return '$year year${year == 1 ? '' : 's'} ago';
  }

  Map<int, int> _ratingCounts() {
    final counts = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final review in _reviews) {
      final r = review.rating.clamp(1, 5);
      counts[r] = (counts[r] ?? 0) + 1;
    }
    return counts;
  }

  List<String> _productTagHierarchy() {
    final path = (_currentProduct.tag.categoryPath ?? '').trim();
    final fromPath =
        path
            .split(RegExp(r'[>/.]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    final fallbackTag = _currentProduct.tag.name.trim();
    final tags = <String>[];
    for (final t in fromPath) {
      if (!tags.any((e) => e.toLowerCase() == t.toLowerCase())) {
        tags.add(t);
      }
    }
    if (fallbackTag.isNotEmpty &&
        !tags.any((e) => e.toLowerCase() == fallbackTag.toLowerCase())) {
      tags.add(fallbackTag);
    }
    return tags;
  }

  bool _shouldShowDescriptionToggle({
    required String text,
    required TextStyle style,
    required double maxWidth,
  }) {
    if (text.trim().isEmpty) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  Widget _buildRatingDistribution() {
    if (_reviews.isEmpty) return const SizedBox.shrink();
    final counts = _ratingCounts();
    final total = _reviews.length;
    return Column(
      children: [5, 4, 3, 2, 1].map((star) {
        final count = counts[star] ?? 0;
        final ratio = total == 0 ? 0.0 : count / total;
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  '$star',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.star_border,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: ratio,
                    backgroundColor: AppColors.border.withValues(alpha: 0.45),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 14,
                child: Text(
                  '$count',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _currentProduct = widget.product!;
      ProductMemoryCache.instance.remember(_currentProduct);
      _hydrateReviewsFromCache();
      _loadReviews(background: _reviews.isNotEmpty);
      _refreshProductData();
      return;
    }
    final pid = widget.productId!;
    final warm = ProductMemoryCache.instance.peek(pid);
    if (warm != null) {
      _currentProduct = warm;
      _isLoadingProduct = false;
      _hydrateReviewsFromCache();
      _loadReviews(background: _reviews.isNotEmpty);
      unawaited(_refreshProductData());
      return;
    }
    // productId ile açıldı: placeholder ile hemen göster, arka planda ürünü yükle
    _currentProduct = _placeholderProduct(pid, widget.productName ?? '');
    _isLoadingProduct = true;
    _hydrateReviewsFromCache();
    _loadReviews(background: _reviews.isNotEmpty);
    _loadProductById();
  }

  void _hydrateReviewsFromCache() {
    final cached = ReviewMemoryCache.instance.peek(_currentProduct.id);
    if (cached == null || cached.isEmpty) return;
    _reviews = cached;
    _isLoadingReviews = false;
    _errorMessage = null;
  }

  ProductDto _placeholderProduct(String id, String name) {
    return ProductDto(
      id: id,
      name: name.isNotEmpty ? name : '...',
      imageURL: '',
      tag: TagDto(id: '', name: ''),
    );
  }

  Future<void> _loadProductById() async {
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      final product = await _productRepository.getProductById(
        widget.productId!,
        firebaseIdToken: token,
      );
      if (!mounted) return;
      setState(() {
        _currentProduct = product;
        _isLoadingProduct = false;
      });
      await _loadLikeCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingProduct = false;
      });
    }
  }

  Future<void> _loadLikeCount() async {
    try {
      final count = await _interactionRepository.getProductLikeCount(
        _currentProduct.id,
      );
      if (!mounted) return;
      setState(() {
        _likeCount = count;
        _hasLoadedLikeCount = true;
      });
    } catch (_) {
      // Hata durumunda mevcut değeri koru ama loading state'ten çık
      if (!mounted) return;
      setState(() {
        _hasLoadedLikeCount = true;
      });
    }
  }

  Future<void> _onChatIconTap(ReviewDto review) async {
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
                    recipientId: int.tryParse(review.ownerId),
                    content: text,
                  );
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Message sent to @${review.ownerUserName}',
                        ),
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
                    'Message @${review.ownerUserName}',
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
                      child:
                          isSending
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

  /// Product'ı backend'den yeniden yükler (rating ve like durumu için)
  Future<void> _refreshProductData() async {
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (token == null) return;

      // Product'ı tamamen yeniden yükle
      final updatedProduct = await _productRepository.getProductById(
        _currentProduct.id,
        firebaseIdToken: token,
        bypassCache: true,
      );

      setState(() {
        _currentProduct = updatedProduct;
      });
      await _loadLikeCount();
    } catch (_) {}
  }

  Future<void> _loadReviews({bool background = false}) async {
    if (!background) {
      setState(() {
        _isLoadingReviews = true;
        _errorMessage = null;
      });
    } else {
      _errorMessage = null;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Kullanıcı giriş yapmamışsa, review'ları token olmadan çekmeyi dene
        try {
          final reviews = await _reviewRepository.getReviewsByProductId(
            _currentProduct.id,
            firebaseIdToken: null,
          );
          ReviewMemoryCache.instance.remember(_currentProduct.id, reviews);
          setState(() {
            _reviews = reviews;
            _isLoadingReviews = false;
          });
          return;
        } catch (e) {
          setState(() {
            _errorMessage = 'Please login to view reviews';
            _isLoadingReviews = false;
          });
          return;
        }
      }

      // Ensure session and get token
      final firebaseIdToken = await _sessionHelper.ensureSession();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Mevcut kullanıcının backend username'ini al (kendi review'larını tespit için)
      try {
        final authService = AuthService();
        final me = await authService.getMe();
        _currentUsername = me.userName;
        _currentUserId = me.id;
      } catch (_) {}

      // Review'ları çek
      final reviews = await _reviewRepository.getReviewsByProductId(
        _currentProduct.id,
        firebaseIdToken: firebaseIdToken,
      );
      ReviewMemoryCache.instance.remember(_currentProduct.id, reviews);

      setState(() {
        _reviews = reviews;
        _isLoadingReviews = false;
      });
    } catch (e) {
      if (background && _reviews.isNotEmpty) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoadingReviews = false;
      });
    }
  }

  Future<void> _toggleLike() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to like products'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // Optimistic update - UI'ı hemen güncelle (loading indicator yok)
    final previousLikeStatus = _currentProduct.isLiked ?? false;
    setState(() {
      _currentProduct = _currentProduct.copyWith(isLiked: !previousLikeStatus);
    });

    try {
      // Token al (session zaten var, sadece token'ı header'a ekle)
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (token == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Backend'e like toggle isteği gönder
      final newLikeStatus = await _interactionRepository.toggleProductLike(
        token,
        _currentProduct.id,
      );

      // Backend'den gelen gerçek durumu güncelle (arka planda, kullanıcı fark etmez)
      setState(() {
        _currentProduct = _currentProduct.copyWith(isLiked: newLikeStatus);
      });
      await _loadLikeCount();
    } catch (e) {
      // Hata durumunda optimistic update'i geri al
      setState(() {
        _currentProduct = _currentProduct.copyWith(isLiked: previousLikeStatus);
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

  Future<void> _onReportProductPressed() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to report a product'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Report product',
              style: AppTextStyles.heading3.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            content: Text(
              'Report "${_currentProduct.name}" to our team?',
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Report'),
              ),
            ],
          ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    try {
      final token = await _sessionHelper.ensureSession();
      if (!mounted) return;
      if (token == null) {
        throw Exception('Please sign in to report a product');
      }
      final reported = await _interactionRepository.reportProduct(
        token,
        _currentProduct.id,
      );
      if (!mounted) return;
      if (reported) {
        await showBrandedOkDialog(context, title: 'Successfully reported');
      } else {
        await showBrandedOkDialog(
          context,
          title: 'Already reported',
          message: 'You have already reported this product.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getUserFriendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _openImagePreview() {
    final imageUrl = _currentProduct.imageURL;
    if (imageUrl.trim().isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Hero(
                    tag:
                        'product_image_${_currentProduct.id}_${_currentProduct.imageURL}',
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        centerTitle: false,
        toolbarHeight: 62,
        titleSpacing: 4,
        title: Text(
          _currentProduct.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyBold.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            height: 1.1,
          ),
        ),
      ),
      body: CustomRefreshIndicator(
        onRefresh: () async {
          await Future.wait([_loadReviews(), _refreshProductData()]);
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(
              top: 0,
              bottom: AppSpacing.xxLarge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// HERO PRODUCT CARD
                Padding(
                  padding: _contentHorizontalPadding,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.medium),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.7),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: _openImagePreview,
                            child: Hero(
                              tag:
                                  'product_image_${_currentProduct.id}_${_currentProduct.imageURL}',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(
                                  _currentProduct.imageURL,
                                  height: 210,
                                  width: 210,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.center,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 210,
                                      width: 210,
                                      color: AppColors.textSecondary.withOpacity(
                                        0.1,
                                      ),
                                      child: const Icon(
                                        Icons.image_not_supported,
                                        color: AppColors.textSecondary,
                                        size: 44,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.medium),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                _productTagHierarchy().map((tag) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: AppColors.border.withValues(
                                            alpha: 0.9,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        tag,
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.small),
                        if ((_currentProduct.description ?? '').trim().isEmpty)
                          Text(
                            'No product description yet.',
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.4,
                              fontSize: 15,
                            ),
                          )
                        else ...[
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final descStyle = AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.35,
                                fontSize: 15,
                              );
                              final description = _currentProduct.description!;
                              final canExpand = _shouldShowDescriptionToggle(
                                text: description,
                                style: descStyle,
                                maxWidth: constraints.maxWidth,
                              );

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    description,
                                    maxLines:
                                        (_isDescriptionExpanded || !canExpand)
                                            ? null
                                            : 3,
                                    overflow:
                                        (_isDescriptionExpanded || !canExpand)
                                            ? TextOverflow.visible
                                            : TextOverflow.ellipsis,
                                    textAlign: TextAlign.start,
                                    style: descStyle,
                                  ),
                                  if (canExpand) ...[
                                    const SizedBox(height: 2),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed:
                                            () => setState(
                                              () =>
                                                  _isDescriptionExpanded =
                                                      !_isDescriptionExpanded,
                                            ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 0,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _isDescriptionExpanded
                                                  ? 'Show less'
                                                  : 'Read more',
                                              style: AppTextStyles.bodySmall
                                                  .copyWith(
                                                    color:
                                                        AppColors.textSecondary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              _isDescriptionExpanded
                                                  ? Icons.expand_less_rounded
                                                  : Icons.expand_more_rounded,
                                              size: 18,
                                              color: AppColors.textSecondary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: AppSpacing.medium),
                        Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: SizedBox(
                                height: 48,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () async {
                                    final result = await Navigator.push(
                                      context,
                                      SlideUpRoute(
                                        page: AddReviewPage(
                                          product: _currentProduct,
                                        ),
                                      ),
                                    );
                                    if (result == true) {
                                      await Future.wait([
                                        _loadReviews(),
                                        _refreshProductData(),
                                      ]);
                                    }
                                  },
                                  child: const Text('Add a Review'),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.medium),
                            Expanded(
                              flex: 1,
                              child: SizedBox(
                                height: 48,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: IconButton(
                                    onPressed: _toggleLike,
                                    splashRadius: 20,
                                    icon: Icon(
                                      _currentProduct.isLiked ?? false
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 22,
                                      color:
                                          _currentProduct.isLiked ?? false
                                              ? AppColors.primary
                                              : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.small),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$_likeCount likes',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _miniIconAction(
                                  icon: Icons.flag_outlined,
                                  onTap:
                                      _isLoadingProduct
                                          ? null
                                          : _onReportProductPressed,
                                ),
                                const SizedBox(width: 8),
                                _miniIconAction(
                                  icon: Icons.compare_arrows_outlined,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => CompareProductSelectPage(
                                              product1: _currentProduct,
                                            ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                _miniIconAction(
                                  customIcon: Image.asset(
                                    'assets/images/Chatbot.png',
                                    width: 24,
                                    height: 24,
                                    fit: BoxFit.contain,
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => ProductAiChatPage(
                                              productId: _currentProduct.id,
                                              productName: _currentProduct.name,
                                            ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.small),
                        Builder(
                          builder: (context) {
                            final rawRating = _currentProduct.averageRating ?? 0.0;
                            final hasRating = productHasMeaningfulRating(rawRating);
                            final rating =
                                (rawRating.isNaN || rawRating.isInfinite)
                                    ? 0.0
                                    : rawRating.clamp(0.0, 5.0);

                            if (!hasRating) return const NewProductBadge();

                            return Container(
                              padding: const EdgeInsets.all(AppSpacing.small),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.border.withValues(alpha: 0.75),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap:
                                        () => setState(
                                          () =>
                                              _isRatingExpanded =
                                                  !_isRatingExpanded,
                                        ),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                        horizontal: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          ...List.generate(5, (index) {
                                            if (rating >= index + 1) {
                                              return const Icon(
                                                Icons.star,
                                                size: 20,
                                                color: AppColors.primary,
                                              );
                                            } else if (rating > index &&
                                                rating < index + 1) {
                                              return SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: Stack(
                                                  children: [
                                                    const Icon(
                                                      Icons.star_border,
                                                      size: 20,
                                                      color:
                                                          AppColors.textSecondary,
                                                    ),
                                                    ClipRect(
                                                      child: Align(
                                                        alignment:
                                                            Alignment.centerLeft,
                                                        widthFactor:
                                                            rating - index,
                                                        child: const Icon(
                                                          Icons.star,
                                                          size: 20,
                                                          color:
                                                              AppColors.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            return const Icon(
                                              Icons.star_border,
                                              size: 20,
                                              color: AppColors.textSecondary,
                                            );
                                          }),
                                          const SizedBox(width: 8),
                                          Text(
                                            rating.toStringAsFixed(1),
                                            style: AppTextStyles.bodyBold
                                                .copyWith(
                                                  color: AppColors.textPrimary,
                                                  fontSize: 16,
                                                ),
                                          ),
                                          const Spacer(),
                                          Icon(
                                            _isRatingExpanded
                                                ? Icons.keyboard_arrow_up_rounded
                                                : Icons
                                                    .keyboard_arrow_down_rounded,
                                            color: AppColors.textSecondary,
                                            size: 22,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  AnimatedCrossFade(
                                    duration: const Duration(milliseconds: 220),
                                    firstChild: const SizedBox.shrink(),
                                    secondChild: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: _buildRatingDistribution(),
                                    ),
                                    crossFadeState:
                                        _isRatingExpanded
                                            ? CrossFadeState.showSecond
                                            : CrossFadeState.showFirst,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.large),

                /// REVIEWS TITLE
                Padding(
                  padding: _contentHorizontalPadding,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Reviews", style: AppTextStyles.heading2),
                      if (_reviews.isNotEmpty)
                        Text(
                          '${_reviews.length} review${_reviews.length > 1 ? 's' : ''}',
                          style: AppTextStyles.bodySecondary.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xLarge),

                /// REVIEWS LIST
                if (_isLoadingReviews)
                  ...List.generate(
                    3,
                    (index) => Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.xxLarge,
                        right: AppSpacing.xxLarge,
                        bottom: AppSpacing.large,
                      ),
                      child: const ReviewCardSkeleton(),
                    ),
                  )
                else if (_errorMessage != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxLarge,
                        vertical: AppSpacing.xxLarge,
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Failed to load reviews: $_errorMessage',
                            style: AppTextStyles.body,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.large),
                          ElevatedButton(
                            onPressed: _loadReviews,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_reviews.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxLarge,
                        vertical: AppSpacing.xxLarge,
                      ),
                      child: Text(
                        'No reviews yet. Be the first to review!',
                        style: AppTextStyles.bodySecondary,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ..._reviews.map(
                    (review) => Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.xxLarge,
                        right: AppSpacing.xxLarge,
                        bottom: AppSpacing.large,
                      ),
                      child: ReviewCard(
                        username: '@${review.ownerUserName}',
                        content: review.description ?? review.title,
                        rating: review.rating,
                        reviewDateLabel: _formatReviewRelativeDate(
                          review.createdAt,
                        ),
                        isSponsored: review.isCollaborative,
                        likeCount: review.likeCount,
                        isLiked: review.isLikedByCurrentUser,
                        isCurrentUser:
                            _currentUserId != null &&
                            review.ownerId.trim() == _currentUserId!.trim(),
                        showChatIcon:
                            _currentUsername != null &&
                            review.ownerUserName.toLowerCase() !=
                                _currentUsername!.toLowerCase(),
                        onReportTap:
                            _currentUserId != null &&
                                    review.ownerId.trim() ==
                                        _currentUserId!.trim()
                                ? null
                                : () async {
                                  await openReviewReportFlow(
                                    context,
                                    reviewId: review.id,
                                  );
                                },
                        onChatTap: () => _onChatIconTap(review),
                        onUsernameTap: () {
                          if (_currentUserId != null &&
                              review.ownerId.trim() == _currentUserId!.trim()) {
                            return;
                          }
                          Navigator.push(
                            context,
                            SlideRightRoute(
                              page: UserProfilePage(
                                userId: review.ownerId,
                                userName: review.ownerUserName,
                                profileImageUrl: review.ownerProfilePhotoUrl,
                              ),
                            ),
                          );
                        },
                        onTap: () async {
                          // Review detail'den dönüldüğünde review listesini yenile
                          final result = await Navigator.push(
                            context,
                            SlideRightRoute(
                              page: ReviewDetailPage(
                                review: review,
                                product: _currentProduct,
                              ),
                            ),
                          );
                          // Review detail'de like yapıldıysa review listesini güncelle
                          if (result == true) {
                            await _loadReviews();
                          }
                        },
                        onLikeTap: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please login to upvote reviews',
                                  ),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                            return;
                          }

                          // Optimistic update - UI'ı hemen güncelle
                          final reviewIndex = _reviews.indexWhere(
                            (r) => r.id == review.id,
                          );
                          if (reviewIndex != -1) {
                            final previousLikeStatus =
                                _reviews[reviewIndex].isLikedByCurrentUser;
                            final previousLikeCount =
                                _reviews[reviewIndex].likeCount;

                            setState(() {
                              _reviews[reviewIndex] = ReviewDto(
                                id: review.id,
                                title: review.title,
                                description: review.description,
                                isCollaborative: review.isCollaborative,
                                rating: review.rating,
                                createdAt: review.createdAt,
                                productId: review.productId,
                                productName: review.productName,
                                ownerId: review.ownerId,
                                ownerUserName: review.ownerUserName,
                                mediaList: review.mediaList,
                                likeCount:
                                    previousLikeStatus
                                        ? (previousLikeCount > 0
                                            ? previousLikeCount - 1
                                            : 0)
                                        : previousLikeCount + 1,
                                isLikedByCurrentUser: !previousLikeStatus,
                              );
                            });
                          }

                          try {
                            // Token al (session zaten var)
                            final token =
                                await _sessionHelper.getTokenAndSetHeader();
                            if (token == null) {
                              throw Exception(
                                'Failed to get Firebase ID token',
                              );
                            }

                            // Upvote toggle yap
                            final newLikeStatus = await _interactionRepository
                                .toggleReviewLike(token, review.id);

                            // Review'ı backend'den yeniden çek (güncel like durumu için)
                            try {
                              final updatedReview = await _reviewRepository
                                  .getReviewById(
                                    review.id,
                                    firebaseIdToken: token,
                                  );

                              // Review listesini güncelle
                              if (reviewIndex != -1) {
                                setState(() {
                                  _reviews[reviewIndex] = updatedReview;
                                });
                              }
                            } catch (e) {
                              // Backend'den çekme başarısız olursa, toggle'dan dönen değeri kullan
                              if (reviewIndex != -1) {
                                final currentReview = _reviews[reviewIndex];
                                setState(() {
                                  _reviews[reviewIndex] = ReviewDto(
                                    id: currentReview.id,
                                    title: currentReview.title,
                                    description: currentReview.description,
                                    isCollaborative:
                                        currentReview.isCollaborative,
                                    rating: currentReview.rating,
                                    createdAt: currentReview.createdAt,
                                    productId: currentReview.productId,
                                    productName: currentReview.productName,
                                    ownerId: currentReview.ownerId,
                                    ownerUserName: currentReview.ownerUserName,
                                    mediaList: currentReview.mediaList,
                                    likeCount:
                                        newLikeStatus
                                            ? (currentReview.likeCount + 1)
                                            : (currentReview.likeCount > 0
                                                ? currentReview.likeCount - 1
                                                : 0),
                                    isLikedByCurrentUser: newLikeStatus,
                                  );
                                });
                              }
                            }
                          } catch (e) {
                            // Hata durumunda optimistic update'i geri al
                            if (reviewIndex != -1) {
                              setState(() {
                                _reviews[reviewIndex] = review;
                              });
                            }
                            if (mounted) {
                              final errorMessage =
                                  ErrorHandler.getUserFriendlyMessage(e);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(errorMessage),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ),

                const SizedBox(height: AppSpacing.xxLarge),
              ],
            ),
          ),
        ),
      ),

    );
  }

  Widget _miniIconAction({
    IconData? icon,
    Widget? customIcon,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 42),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child:
          customIcon ?? Icon(icon, size: 21, color: AppColors.textSecondary),
    );
  }
}

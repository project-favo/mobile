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
import '../../../../../core/cache/product_memory_cache.dart';
import '../../../../../core/cache/review_memory_cache.dart';
import '../../../../../core/utils/exceptions.dart';
import '../../../../../core/utils/content_availability_messages.dart';
import '../../../../../core/utils/content_unavailable_dialog.dart';
import '../../../../../core/utils/app_datetime.dart';
import '../../../../../core/utils/entity_active.dart';
import '../../../../../core/utils/user_profile_navigation.dart';
import '../../../../../core/utils/in_flight_id_lock.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/utils/review_report_storage.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import 'review_page.dart';
import '../../home_page.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/repositories/message_repository.dart';
import '../../../data/services/auth_service.dart';
import '../widgets/report_review_sheet.dart';
import '../widgets/review_delete_flow.dart';
import 'add_review_page.dart';

class ReviewDetailPage extends StatefulWidget {
  final ReviewDto review;
  final ProductDto product;

  /// [Navigator.pop] ile dönülür — ürün askı / kaldırma sonrası otomatik çıkış.
  static const String popResultProductSuspended =
      'review_detail_product_suspended';

  const ReviewDetailPage({
    super.key,
    required this.review,
    required this.product,
  });

  @override
  State<ReviewDetailPage> createState() => _ReviewDetailPageState();
}

class _ReviewDetailPageState extends State<ReviewDetailPage>
    with WidgetsBindingObserver {
  final InteractionRepository _interactionRepository = InteractionRepository();
  final ProductRepository _productRepository = ProductRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final ApiClient _apiClient = ApiClient();
  late ReviewDto _currentReview;
  /// Açıldığında [widget.product], poll ile GET’te tazelenebilir.
  late ProductDto _currentProduct;
  final MessageRepository _messageRepository = MessageRepository();

  /// Şikayet butonunu gizlemek için (kendi yorumu).
  String? _viewerUserId;

  /// Media futures cached by media ID — prevents FutureBuilder from restarting on every rebuild.
  final Map<String, Future<Uint8List?>> _mediaFutures = {};
  final InFlightFlag _reviewDetailLikeLock = InFlightFlag();
  final InFlightFlag _reviewDeleteLock = InFlightFlag();

  /// Ürün askı / vitrin dışı; [canPop] yokken tam ekran yedek.
  bool _productListingBlocked = false;
  bool _productListingCheckDone = false;
  static const Duration _listingPollInterval = Duration(seconds: 5);
  Timer? _listingPollTimer;
  bool _poppedForListingGone = false;
  /// Son bildiğimiz home ilk sayfa (50) içindeyiz bilgisi — true→false askı/çıkarma ile uyumlu.
  bool? _lastProductOnHomeFirstPage;
  /// In [initState], inactive review/product: show [showContentUnavailableDialog] before the first frame.
  bool _invalidInitialRoute = false;

  bool get _isOwnReview {
    if (CurrentUserCache.instance.isMyReview(_currentReview)) return true;
    return _viewerUserId != null &&
        _viewerUserId!.trim() == _currentReview.ownerId.trim();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentReview = widget.review;
    _currentProduct = widget.product;
    if (!isReviewEntityVisible(_currentReview) ||
        !isProductEntityActive(_currentProduct)) {
      _invalidInitialRoute = true;
      _productListingCheckDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _navigateBackWithNotice(
              detail: !isProductEntityActive(_currentProduct)
                  ? kMessageProductNoLongerAvailable
                  : kMessageReviewNoLongerAvailable,
            ),
          );
        }
      });
      return;
    }
    _initMediaFutures();
    final w = CurrentUserCache.instance;
    if (w.isMyReview(_currentReview)) {
      _viewerUserId = w.userId;
    }
    unawaited(_loadViewerId());
    unawaited(
      ReviewReportStorage.hydrateForCurrentUser().then((_) {
        if (mounted) setState(() {});
      }),
    );
    // Defer the refresh so the first frame renders fully before making an API call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_revalidateProductListing());
        unawaited(_refreshReview());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _listingPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_pollProductAndReviewStillPresent());
    }
  }

  void _startListingPoll() {
    _listingPollTimer?.cancel();
    // İlk tetik: [Timer.periodic] Dart'ta ilk callback'i 5 sn sonra atar; vitrin tespitini geciktirmesin.
    unawaited(_pollProductAndReviewStillPresent());
    _listingPollTimer = Timer.periodic(_listingPollInterval, (_) {
      if (!mounted) return;
      unawaited(_pollProductAndReviewStillPresent());
    });
  }

  /// GET /api/products/home `page=0&size=50` — hata: yanlış geri sarma riskine karşı 'vitrinde' kabul.
  Future<bool> _isProductIdOnHomeFirst50(
    String productId,
    String? token,
  ) async {
    final id = productId.trim();
    if (id.isEmpty) return true;
    try {
      final feed = await _productRepository.getHomeFeed(
        page: 0,
        size: 50,
        firebaseIdToken: token,
      );
      final on = feed.content.map((e) => e.id.trim()).toSet();
      return on.contains(id);
    } catch (_) {
      return true;
    }
  }

  Future<void> _seedLastHomeSnapshot(ProductDto p, String? token) async {
    if (!mounted) return;
    final on = await _isProductIdOnHomeFirst50(p.id, token);
    if (!mounted) return;
    _lastProductOnHomeFirstPage = on;
  }

  static bool _reviewSnapshotChanged(ReviewDto a, ReviewDto b) {
    if (a.id != b.id) return true;
    return a.rating != b.rating ||
        a.likeCount != b.likeCount ||
        a.isLikedByCurrentUser != b.isLikedByCurrentUser ||
        a.isProductNotListed != b.isProductNotListed ||
        a.isReviewInactive != b.isReviewInactive ||
        a.title != b.title ||
        (a.description ?? '') != (b.description ?? '') ||
        a.mediaList.length != b.mediaList.length;
  }

  static bool _productSnapshotChangedForDetail(ProductDto a, ProductDto b) {
    return a.name != b.name ||
        a.imageURL != b.imageURL ||
        (a.description ?? '') != (b.description ?? '') ||
        a.isProductNotListed != b.isProductNotListed ||
        (a.averageRating ?? 0) != (b.averageRating ?? 0) ||
        a.isLiked != b.isLiked;
  }

  void _applyMergedReviewToMemoryCache(ReviewDto r) {
    final list = ReviewMemoryCache.instance.peek(r.productId) ?? <ReviewDto>[];
    final next = List<ReviewDto>.from(list);
    final i = next.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      next[i] = r;
    } else {
      next.add(r);
    }
    ReviewMemoryCache.instance.remember(r.productId, next);
  }

  /// 5 sn: GET yorum + ürün; yalnızca veri farkı varsa [setState] (titreme yok). Askı/404’te çık.
  /// Token yok: yine de [bypassCache] GET ürün (cache’de kalmış “aktif” [ProductDto] dönmesin).
  Future<void> _pollProductAndReviewStillPresent() async {
    if (!mounted || _poppedForListingGone) return;
    final token = await _sessionHelper.getTokenAndSetHeader();
    if (token != null) {
      ReviewDto? r;
      try {
        r = await _reviewRepository.getReviewById(
          _currentReview.id,
          firebaseIdToken: token,
        );
      } on ReviewNotAvailableException {
        if (mounted) {
          await _navigateBackWithNotice(
            detail: kMessageGenericContentNoLongerAvailable,
          );
        }
        return;
      } on DioException catch (e) {
        final c = e.response?.statusCode;
        if (c == 404 || c == 401) {
          if (mounted) {
            await _navigateBackWithNotice(
              detail: kMessageGenericContentNoLongerAvailable,
            );
          }
          return;
        }
      } catch (_) {}
      if (r != null) {
        final freshReview = r;
        if (!mounted) return;
        if (!isReviewEntityVisible(freshReview)) {
          await _navigateBackWithNotice(detail: kMessageReviewNoLongerAvailable);
          return;
        }
        if (_reviewSnapshotChanged(freshReview, _currentReview)) {
          if (mounted) {
            setState(() => _currentReview = freshReview);
            _initMediaFutures();
          }
          if (isReviewEntityVisible(freshReview)) {
            _applyMergedReviewToMemoryCache(freshReview);
          }
        }
      }
    }
    try {
      final p = await _productRepository.getProductById(
        _currentProduct.id,
        firebaseIdToken: token,
        bypassCache: true,
      );
      if (!mounted) return;
      if (p.isUnavailableForStorefront) {
        await _navigateBackWithNotice();
        return;
      }
      if (_productSnapshotChangedForDetail(p, _currentProduct)) {
        if (mounted) {
          setState(() => _currentProduct = p);
        }
        ProductMemoryCache.instance.remember(p);
      }
      final onHome = await _isProductIdOnHomeFirst50(p.id, token);
      if (!mounted) return;
      if (_lastProductOnHomeFirstPage == true && onHome == false) {
        await _navigateBackWithNotice();
        return;
      }
      _lastProductOnHomeFirstPage = onHome;
    } on ProductNotAvailableException {
      if (!mounted) return;
      await _navigateBackWithNotice();
    } catch (_) {}
  }

  /// [detail] defaults to the product copy. Always returns to [HomePage] (not the previous page).
  Future<void> _navigateBackWithNotice({String? detail}) async {
    if (!mounted || _poppedForListingGone) return;
    _poppedForListingGone = true;
    _listingPollTimer?.cancel();
    _listingPollTimer = null;
    final nav = Navigator.of(context);
    final body = detail ?? kMessageProductNoLongerAvailable;
    final String title;
    if (body == kMessageReviewNoLongerAvailable) {
      title = kTitleReviewUnavailable;
    } else if (body == kMessageGenericContentNoLongerAvailable) {
      title = kTitleContentUnavailable;
    } else {
      title = kTitleProductUnavailable;
    }
    ProductMemoryCache.instance.remove(_currentProduct.id);
    ReviewMemoryCache.instance.removeReviewFromProduct(
      _currentProduct.id,
      _currentReview.id,
    );
    await showContentUnavailableDialog(
      context,
      title: title,
      message: body,
      onContinue: () async {
        if (!mounted) return;
        await nav.pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(builder: (_) => const HomePage()),
          (route) => false,
        );
      },
    );
  }

  /// Token yok / giriş yok: yorum API’si yok; sadece taze [getProductById] ile askı/404 tespit et.
  Future<void> _revalidateProductListingProductOnly() async {
    if (!isReviewEntityVisible(widget.review) ||
        !isProductEntityActive(widget.product)) {
      if (mounted) {
        await _navigateBackWithNotice();
      }
      return;
    }
    try {
      final p = await _productRepository.getProductById(
        _currentProduct.id,
        firebaseIdToken: null,
        bypassCache: true,
      );
      if (!mounted) return;
      if (p.isUnavailableForStorefront) {
        if (mounted) {
          await _navigateBackWithNotice();
        }
        return;
      }
      await _seedLastHomeSnapshot(p, null);
      if (!mounted) return;
      if (mounted) {
        setState(() {
          _currentProduct = p;
          _productListingBlocked = false;
          _productListingCheckDone = true;
        });
        ProductMemoryCache.instance.remember(p);
        _startListingPoll();
      }
    } on ProductNotAvailableException {
      if (mounted) {
        await _navigateBackWithNotice();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _productListingCheckDone = true);
      }
    }
  }

  /// Profil dışı rotalarda eski [ProductDto] ile gelinebilir; GET ile teyit.
  Future<void> _revalidateProductListing() async {
    if (!isReviewEntityVisible(widget.review) ||
        !isProductEntityActive(widget.product)) {
      if (mounted) {
        await _navigateBackWithNotice();
      }
      return;
    }
    final token = await _sessionHelper.getTokenAndSetHeader();
    if (token == null) {
      await _revalidateProductListingProductOnly();
      return;
    }
    ReviewDto? refreshedReview;
    try {
      final r = await _reviewRepository.getReviewById(
        _currentReview.id,
        firebaseIdToken: token,
      );
      if (!mounted) return;
      if (!isReviewEntityVisible(r)) {
        if (mounted) {
          await _navigateBackWithNotice(
            detail: kMessageReviewNoLongerAvailable,
          );
        }
        return;
      }
      refreshedReview = r;
    } on ReviewNotAvailableException {
      if (mounted) {
        await _navigateBackWithNotice(
          detail: kMessageGenericContentNoLongerAvailable,
        );
      }
      return;
    } on DioException catch (e) {
      final c = e.response?.statusCode;
      if (c == 404 || c == 401) {
        if (mounted) {
          await _navigateBackWithNotice(
            detail: kMessageGenericContentNoLongerAvailable,
          );
        }
        return;
      }
    } catch (_) {
      // Yorum ucu geçici hata: ürün teyidini dene
    }
    if (!mounted) return;
    try {
      final p = await _productRepository.getProductById(
        _currentProduct.id,
        firebaseIdToken: token,
        bypassCache: true,
      );
      if (!mounted) return;
      if (p.isUnavailableForStorefront) {
        if (mounted) {
          await _navigateBackWithNotice();
        }
        return;
      }
      await _seedLastHomeSnapshot(p, token);
      if (!mounted) return;
      if (mounted) {
        setState(() {
          if (refreshedReview != null) {
            _currentReview = refreshedReview;
          }
          _currentProduct = p;
          _productListingBlocked = false;
          _productListingCheckDone = true;
        });
        if (refreshedReview != null) {
          _initMediaFutures();
        }
        ProductMemoryCache.instance.remember(p);
        _startListingPoll();
      }
    } on ProductNotAvailableException {
      if (mounted) {
        await _navigateBackWithNotice();
      }
      return;
    } catch (_) {
      // Ürün GET’i başarısız: eski [_currentProduct] ile home anı tohumlamak yanlış vitrin/askı sinyali üretir.
      if (mounted) {
        setState(() {
          if (refreshedReview != null) {
            _currentReview = refreshedReview;
          }
          _productListingBlocked = false;
          _productListingCheckDone = true;
        });
        if (refreshedReview != null) {
          _initMediaFutures();
        }
        _startListingPoll();
      }
      return;
    }
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
      if (!mounted) return;
      if (!isReviewEntityVisible(updatedReview)) {
        await _navigateBackWithNotice(detail: kMessageReviewNoLongerAvailable);
        return;
      }

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
    } on ReviewNotAvailableException {
      if (mounted) {
        await _navigateBackWithNotice(
          detail: kMessageGenericContentNoLongerAvailable,
        );
      }
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

  Future<void> _openEditReview() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder:
            (_) => AddReviewPage(
              product: widget.product,
              reviewToEdit: _currentReview,
            ),
      ),
    );
    if (ok == true && mounted) {
      await _refreshReview();
    }
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
      final response = await _apiClient.dio
          .get(
            path,
            options: Options(
              responseType: ResponseType.bytes,
              headers: {'Accept': 'image/*'},
            ),
          )
          .timeout(const Duration(seconds: 10));

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
                        content: Text(
                          'Message sent to @${_currentReview.ownerUserName}',
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

  /// Aktif vitrin ürünü: anında product detail. Sinyal kötüyse bekleme yok, dialog + pop (5 sn poll taze veriyi getirir).
  void _onProductCardTap() {
    if (!mounted) return;
    if (_currentProduct.isUnavailableForStorefront) {
      unawaited(_navigateBackWithNotice());
      return;
    }
    final pid = _currentProduct.id.trim().isNotEmpty
        ? _currentProduct.id
        : _currentReview.productId.trim();
    if (pid.isEmpty) return;
    final name = _currentProduct.name.trim().isNotEmpty
        ? _currentProduct.name
        : _currentReview.productName;
    Navigator.push<void>(
      context,
      SlideRightRoute(
        page: ReviewPage(
          product: _currentProduct.id.trim().isNotEmpty
              ? _currentProduct
              : null,
          productId: pid,
          productName: name,
        ),
      ),
    );
  }

  void _openOwnerProfile() {
    if (_isOwnReview) {
      return;
    }
    openUserProfileIfActive(
      context,
      userId: _currentReview.ownerId,
      userName: _currentReview.ownerUserName,
      profileImageUrl: _currentReview.ownerProfilePhotoUrl,
    );
  }

  /// Tarih formatını düzenler
  String _formatDate(String dateString) {
    return formatDateTimeFromBackend(dateString, fallback: dateString);
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
        ownerProfilePhotoUrl: _currentReview.ownerProfilePhotoUrl,
        mediaList: _currentReview.mediaList,
        likeCount:
            previousLikeStatus
                ? (previousLikeCount > 0 ? previousLikeCount - 1 : 0)
                : previousLikeCount + 1,
        isLikedByCurrentUser: !previousLikeStatus,
        isProductNotListed: _currentReview.isProductNotListed,
        isReviewInactive: _currentReview.isReviewInactive,
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
          ownerProfilePhotoUrl: _currentReview.ownerProfilePhotoUrl,
          mediaList: _currentReview.mediaList,
          likeCount:
              newLikeStatus
                  ? (previousLikeCount + 1)
                  : (previousLikeCount > 0 ? previousLikeCount - 1 : 0),
          isLikedByCurrentUser: newLikeStatus,
          isProductNotListed: _currentReview.isProductNotListed,
          isReviewInactive: _currentReview.isReviewInactive,
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
          ownerProfilePhotoUrl: _currentReview.ownerProfilePhotoUrl,
          mediaList: _currentReview.mediaList,
          likeCount: previousLikeCount,
          isLikedByCurrentUser: previousLikeStatus,
          isProductNotListed: _currentReview.isProductNotListed,
          isReviewInactive: _currentReview.isReviewInactive,
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

  Widget _buildProductSuspendedBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'SUSPENDED',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.large),
            Text(
              'This product is no longer available. Review details are hidden until the product is back.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xLarge),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_invalidInitialRoute || _poppedForListingGone) {
      return const Scaffold(
        body: SizedBox.shrink(),
      );
    }
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
        title: const Text('Review Details', style: AppTextStyles.heading2),
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
      body:
          !_productListingCheckDone
              ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              )
              : _productListingBlocked
              ? _buildProductSuspendedBody(context)
              : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                  padding: const EdgeInsets.all(
                                    AppSpacing.large,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: AppColors.border.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      ProfileAvatarImage(
                                        size: 48,
                                        imageUrl:
                                            _currentReview.ownerProfilePhotoUrl,
                                        fallbackInitial:
                                            _currentReview.ownerUserName,
                                      ),
                                      const SizedBox(width: AppSpacing.medium),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  '@${_currentReview.ownerUserName}',
                                                  style: AppTextStyles.bodyBold
                                                      .copyWith(fontSize: 17),
                                                ),
                                                if (_currentReview
                                                    .isCollaborative) ...[
                                                  const SizedBox(
                                                    width: AppSpacing.small,
                                                  ),
                                                  Text(
                                                    'Sponsored',
                                                    style: AppTextStyles.chip
                                                        .copyWith(
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
                                              style: AppTextStyles.bodySmall
                                                  .copyWith(
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
                                    color:
                                        index < _currentReview.rating
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
                                onTap: _onProductCardTap,
                                child: Container(
                                  padding: const EdgeInsets.all(
                                    AppSpacing.large,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.textSecondary.withOpacity(
                                      0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          _currentProduct.imageURL,
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.contain,
                                          alignment: Alignment.center,
                                          gaplessPlayback: true,
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return Container(
                                              width: 100,
                                              height: 100,
                                              color: AppColors.textSecondary
                                                  .withOpacity(0.1),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _currentProduct.name,
                                              style: AppTextStyles.bodyBold,
                                            ),
                                            if (_currentProduct.description !=
                                                    null &&
                                                _currentProduct
                                                    .description!
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                _currentProduct.description!,
                                                style: AppTextStyles.bodySmall
                                                    .copyWith(
                                                      color: AppColors
                                                          .textSecondary,
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
                                        color: AppColors.textSecondary
                                            .withOpacity(0.6),
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
                                  separatorBuilder:
                                      (_, __) => const SizedBox(
                                        width: AppSpacing.medium,
                                      ),
                                  itemBuilder: (context, index) {
                                    final media =
                                        _currentReview.mediaList[index];
                                    // Backend'den direkt URL geliyorsa onu kullan, yoksa id'den oluştur
                                    final mediaUrl = media.getMediaUrl(
                                      ApiConfig.baseUrl,
                                    );

                                    // Eğer backend'den direkt URL geliyorsa, Image.network kullan
                                    if (media.url != null &&
                                        media.url!.isNotEmpty) {
                                      return GestureDetector(
                                        onTap:
                                            () => _openMediaPreview(media.url!),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.network(
                                            media.url!,
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                            errorBuilder: (
                                              context,
                                              error,
                                              stackTrace,
                                            ) {
                                              return Container(
                                                width: 120,
                                                height: 120,
                                                decoration: BoxDecoration(
                                                  color: AppColors.textSecondary
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.image_not_supported,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    }

                                    if (media.imageUrl != null &&
                                        media.imageUrl!.isNotEmpty) {
                                      return GestureDetector(
                                        onTap:
                                            () => _openMediaPreview(
                                              media.imageUrl!,
                                            ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.network(
                                            media.imageUrl!,
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                            errorBuilder: (
                                              context,
                                              error,
                                              stackTrace,
                                            ) {
                                              return Container(
                                                width: 120,
                                                height: 120,
                                                decoration: BoxDecoration(
                                                  color: AppColors.textSecondary
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.image_not_supported,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    }

                                    // Backend'den URL gelmiyorsa, authentication ile yükle
                                    return FutureBuilder<Uint8List?>(
                                      future:
                                          _mediaFutures[media.id] ??
                                          (_mediaFutures[media
                                              .id] = _loadMediaImage(mediaUrl)),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return Container(
                                            width: 120,
                                            height: 120,
                                            decoration: BoxDecoration(
                                              color: AppColors.textSecondary
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          );
                                        }

                                        if (snapshot.hasError ||
                                            snapshot.data == null) {
                                          return Container(
                                            width: 120,
                                            height: 120,
                                            decoration: BoxDecoration(
                                              color: AppColors.textSecondary
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
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
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      body: SafeArea(
                                                        child: Stack(
                                                          children: [
                                                            Center(
                                                              child: InteractiveViewer(
                                                                minScale: 1,
                                                                maxScale: 5,
                                                                child: Image.memory(
                                                                  snapshot
                                                                      .data!,
                                                                  fit:
                                                                      BoxFit
                                                                          .contain,
                                                                ),
                                                              ),
                                                            ),
                                                            Positioned(
                                                              top: 8,
                                                              right: 8,
                                                              child: IconButton(
                                                                onPressed:
                                                                    () =>
                                                                        Navigator.of(
                                                                          ctx,
                                                                        ).pop(),
                                                                icon: const Icon(
                                                                  Icons.close,
                                                                  color:
                                                                      Colors
                                                                          .white,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                              ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.memory(
                                              snapshot.data!,
                                              width: 120,
                                              height: 120,
                                              fit: BoxFit.cover,
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) {
                                                return Container(
                                                  width: 120,
                                                  height: 120,
                                                  color: AppColors.textSecondary
                                                      .withOpacity(0.1),
                                                  child: const Icon(
                                                    Icons.image_not_supported,
                                                    color:
                                                        AppColors.textSecondary,
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
                                  color: AppColors.textSecondary.withOpacity(
                                    0.05,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.textSecondary.withOpacity(
                                      0.2,
                                    ),
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
                                border: Border.all(
                                  color: AppColors.border.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              child: Text(
                                _currentReview.description ??
                                    _currentReview.title,
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
                  _buildBottomActionsBar(context),
                ],
              ),
    );
  }

  /// Alt: kendi yorumu — Like, Update, Delete; başkası — Like, Report.
  Widget _buildBottomActionsBar(BuildContext context) {
    const barH = 48.0;
    final likeStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      minimumSize: const Size(0, barH),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final updateStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      side: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      minimumSize: const Size(0, barH),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final deleteStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.textSecondary,
      side: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      minimumSize: const Size(0, barH),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.xLarge,
        AppSpacing.small,
        AppSpacing.xLarge,
        AppSpacing.small,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child:
            _isOwnReview
                ? Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _toggleLike,
                        style: likeStyle,
                        icon: Icon(
                          _currentReview.isLikedByCurrentUser
                              ? Icons.thumb_up
                              : Icons.thumb_up_alt_outlined,
                          size: 18,
                          color:
                              _currentReview.isLikedByCurrentUser
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                        ),
                        label: Text(
                          '${_currentReview.likeCount}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color:
                                _currentReview.isLikedByCurrentUser
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openEditReview,
                        style: updateStyle,
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          'Update',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _onDeleteReview,
                        style: deleteStyle,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        label: Text(
                          'Delete',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
                : Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _toggleLike,
                        style: likeStyle,
                        icon: Icon(
                          _currentReview.isLikedByCurrentUser
                              ? Icons.thumb_up
                              : Icons.thumb_up_alt_outlined,
                          size: 18,
                          color:
                              _currentReview.isLikedByCurrentUser
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                        ),
                        label: Text(
                          '${_currentReview.likeCount}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color:
                                _currentReview.isLikedByCurrentUser
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () async {
                          await openReviewReportFlow(
                            context,
                            reviewId: _currentReview.id,
                          );
                          if (mounted) setState(() {});
                        },
                        style: likeStyle,
                        icon: Icon(
                          ReviewReportStorage.hasReportedSync(_currentReview.id)
                              ? Icons.flag
                              : Icons.flag_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          'Report',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}

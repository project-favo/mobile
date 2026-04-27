import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/config/api_config.dart';
import '../../../../../core/config/app_background_timers.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/cache/current_user_cache.dart';
import '../../../../../core/cache/self_review_like_local_prefs.dart';
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
import '../../../../../core/widgets/custom_snack_bar.dart';
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
  /// Poll GET’i like toggle’dan önce başladıysa dönen eski satırı uygulama (ana sayfa like epoch ile aynı fikir).
  int _reviewDetailPollBarrierEpoch = 0;

  /// Ürün askı / vitrin dışı; [canPop] yokken tam ekran yedek.
  bool _productListingBlocked = false;
  bool _productListingCheckDone = false;
  static const Duration _listingPollInterval =
      AppBackgroundTimers.standardListPoll;
  Timer? _listingPollTimer;
  bool _poppedForListingGone = false;
  /// Son bildiğimiz home ilk sayfa (50) içindeyiz bilgisi — true→false askı/çıkarma ile uyumlu.
  bool? _lastProductOnHomeFirstPage;
  /// In [initState], inactive review/product: show [showContentUnavailableDialog] before the first frame.
  bool _invalidInitialRoute = false;

  /// Sunucu kendi yorumunu beğenmeyi reddederken yerel +1 / liked gösterimi.
  bool _selfLikeLocalBoost = false;

  static const Color _pageBackground = Color(0xFFF4F5F7);
  static const Color _fieldFill = Color(0xFFF9FAFB);
  static const Color _starEmpty = Color(0xFFD1D5DB);
  static const Color _starFilled = Color(0xFFF5A623);

  bool get _isOwnReview {
    if (CurrentUserCache.instance.isMyReview(_currentReview)) return true;
    return _viewerUserId != null &&
        _viewerUserId!.trim() == _currentReview.ownerId.trim();
  }

  ReviewDto get _reviewForLikeBar =>
      SelfReviewLikeDisplay.mergeServerRowWithBoostMap(
        _currentReview,
        _selfLikeLocalBoost ? {_currentReview.id: true} : {},
      );

  Future<void> _hydrateSelfLikeLocalBoostFromPrefs() async {
    if (!CurrentUserCache.instance.isMyReview(_currentReview)) return;
    final uid =
        (_viewerUserId ?? CurrentUserCache.instance.userId)?.trim() ?? '';
    if (uid.isEmpty) return;
    final m = await SelfReviewLikeLocalPrefs.instance.loadBoostMap(uid);
    final b = m[_currentReview.id] == true;
    if (!mounted) return;
    setState(() => _selfLikeLocalBoost = b);
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
    unawaited(_hydrateSelfLikeLocalBoostFromPrefs());
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

  /// Aynı sayıda medya olsa bile id/url değişince tazelensin (düzenleme sonrası galeri).
  static String _mediaListSignature(ReviewDto r) {
    final keys = r.mediaList
        .map((m) {
          final id = m.id.trim();
          if (id.isNotEmpty) return 'id:$id';
          final u = (m.url ?? '').trim();
          if (u.isNotEmpty) return 'u:$u';
          final i = (m.imageUrl ?? '').trim();
          if (i.isNotEmpty) return 'i:$i';
          return 'm:${m.mimeType}:${m.uploadDate}';
        })
        .toList()
      ..sort();
    return keys.join('\u001e');
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
        a.mediaList.length != b.mediaList.length ||
        _mediaListSignature(a) != _mediaListSignature(b);
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
    final reviewPollBarrierAtStart = _reviewDetailPollBarrierEpoch;
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
          final allowApplyReview =
              mounted &&
              !_reviewDetailLikeLock.isHeld &&
              _reviewDetailPollBarrierEpoch == reviewPollBarrierAtStart;
          if (allowApplyReview) {
            setState(() => _currentReview = freshReview);
            _initMediaFutures();
          }
          if (allowApplyReview && isReviewEntityVisible(freshReview)) {
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

  Uri get _apiBaseUri => Uri.parse(ApiConfig.baseUrl);

  String get _apiBaseNoTrailingSlash {
    final b = ApiConfig.baseUrl;
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  /// Dio ile yüklemek için mutlak URL.
  String _toAbsoluteMediaUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return ApiConfig.baseUrl;
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    final base = _apiBaseNoTrailingSlash;
    if (t.startsWith('/')) return '$base$t';
    return '$base/$t';
  }

  /// Gerçek dış CDN (Bearer gerektirmeyen düz HTTP görüntü).
  bool _isAbsoluteOffSiteMediaUrl(String s) {
    final t = s.trim();
    if (t.isEmpty || t.startsWith('/')) return false;
    final uri = Uri.tryParse(t);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    return uri.host != _apiBaseUri.host;
  }

  /// Aynı origin / göreli yollar token ile [Image.memory]; yalnızca farklı host’ta [Image.network].
  bool _usePlainNetworkImageFor(ReviewMediaDto media) {
    final u = (media.url ?? '').trim();
    final i = (media.imageUrl ?? '').trim();
    if (u.isEmpty && i.isEmpty) return false;
    final primary = u.isNotEmpty ? u : i;
    return _isAbsoluteOffSiteMediaUrl(primary);
  }

  String _authenticatedFetchUrlFor(ReviewMediaDto media) {
    final u = (media.url ?? '').trim();
    final i = (media.imageUrl ?? '').trim();
    final primary = u.isNotEmpty ? u : i;
    if (primary.isEmpty) return media.getMediaUrl(ApiConfig.baseUrl);
    return _toAbsoluteMediaUrl(primary);
  }

  /// Auth gerektiren URL’ler için; boş [ReviewMediaDto.id] çakışmalarını önler.
  String _mediaFutureKey(ReviewMediaDto media) {
    final id = media.id.trim();
    if (id.isNotEmpty) return id;
    return 'u:${_authenticatedFetchUrlFor(media)}';
  }

  /// Pre-creates and caches a Future for each auth-required media item.
  void _initMediaFutures() {
    final keysInUse = <String>{};
    for (final media in _currentReview.mediaList) {
      keysInUse.add(_mediaFutureKey(media));
    }
    _mediaFutures.removeWhere((k, _) => !keysInUse.contains(k));
    for (final media in _currentReview.mediaList) {
      if (_usePlainNetworkImageFor(media)) continue;
      final fetchUrl = _authenticatedFetchUrlFor(media);
      final key = _mediaFutureKey(media);
      _mediaFutures.putIfAbsent(key, () => _loadMediaImage(fetchUrl));
    }
  }

  bool get _canShowChatIcon {
    if (FirebaseAuth.instance.currentUser == null) return false;
    if (_isOwnReview) return false;
    return true;
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

      final oldMediaSig = _mediaListSignature(_currentReview);
      setState(() {
        _currentReview = updatedReview;
        if (viewerId != null && viewerId.trim().isNotEmpty) {
          _viewerUserId = viewerId;
        }
        if (CurrentUserCache.instance.isMyReview(updatedReview) &&
            updatedReview.isLikedByCurrentUser) {
          _selfLikeLocalBoost = false;
        }
      });
      final uidClear =
          (viewerId ?? CurrentUserCache.instance.userId)?.trim() ?? '';
      if (uidClear.isNotEmpty &&
          CurrentUserCache.instance.isMyReview(updatedReview) &&
          updatedReview.isLikedByCurrentUser) {
        unawaited(
          SelfReviewLikeLocalPrefs.instance.setBoost(
            uidClear,
            updatedReview.id,
            false,
          ),
        );
      }
      if (_mediaListSignature(_currentReview) != oldMediaSig) {
        _mediaFutures.clear();
      }
      _initMediaFutures();
      if (CurrentUserCache.instance.isMyReview(_currentReview) &&
          !_currentReview.isLikedByCurrentUser) {
        unawaited(_hydrateSelfLikeLocalBoostFromPrefs());
      }
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
      unawaited(_hydrateSelfLikeLocalBoostFromPrefs());
      return;
    }
    try {
      final me = await AuthService().getMe();
      if (!mounted) return;
      setState(() => _viewerUserId = me.id);
      unawaited(_hydrateSelfLikeLocalBoostFromPrefs());
    } catch (_) {}
  }

  Future<void> _openEditReview() async {
    ReviewDto reviewForEdit = _currentReview;
    try {
      final token = await _sessionHelper.ensureSession();
      if (token != null) {
        reviewForEdit = await _reviewRepository.getReviewById(
          _currentReview.id,
          firebaseIdToken: token,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder:
            (_) => AddReviewPage(
              product: _currentProduct,
              reviewToEdit: reviewForEdit,
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
        CustomSnackBar.show(
          context,
          message: 'Please login to send messages',
          variant: CustomSnackBarVariant.error,
        );
      }
      return;
    }

    final controller = TextEditingController();
    bool isSending = false;
    final pageContext = context;

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
                  if (!context.mounted) return;
                  FocusManager.instance.primaryFocus?.unfocus();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!pageContext.mounted) return;
                      CustomSnackBar.show(
                        pageContext,
                        message:
                            'Message sent to @${_currentReview.ownerUserName}',
                        variant: CustomSnackBarVariant.success,
                      );
                    });
                  });
                } catch (e) {
                  final msg = ErrorHandler.getUserFriendlyMessage(e);
                  if (context.mounted) {
                    CustomSnackBar.show(
                      context,
                      message: msg,
                      variant: CustomSnackBarVariant.error,
                    );
                  } else if (mounted && pageContext.mounted) {
                    CustomSnackBar.show(
                      pageContext,
                      message: msg,
                      variant: CustomSnackBarVariant.error,
                    );
                  }
                  if (context.mounted) {
                    setState(() => isSending = false);
                  }
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
    final t = imageUrl.trim();
    if (t.isEmpty) return;
    if (!_isAbsoluteOffSiteMediaUrl(t)) {
      unawaited(_openAuthenticatedMediaPreview(t));
      return;
    }
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
                        t,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (context, error, stackTrace) => Container(
                              width: 240,
                              height: 240,
                              color: AppColors.textSecondary.withValues(alpha: 0.1),
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

  Future<void> _openAuthenticatedMediaPreview(String rawUrl) async {
    final url = _toAbsoluteMediaUrl(rawUrl);
    final bytes = await _loadMediaImage(url);
    if (!mounted) return;
    if (bytes == null) return;
    await showDialog<void>(
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
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
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
        CustomSnackBar.show(
          context,
          message: 'Please login to upvote reviews',
          variant: CustomSnackBarVariant.error,
        );
      }
      return;
    }

    if (!_reviewDetailLikeLock.tryEnter()) return;

    final serverSnap = _currentReview;
    ReviewDto? nonOwnLikeOptimisticRow;
    final boostBeforeTap = _selfLikeLocalBoost;
    final displayLikedBeforeTap =
        serverSnap.isLikedByCurrentUser || boostBeforeTap;

    if (_isOwnReview) {
      final target = !displayLikedBeforeTap;
      setState(() {
        _selfLikeLocalBoost = target && !serverSnap.isLikedByCurrentUser;
      });
      final uidOptimistic =
          (_viewerUserId ?? CurrentUserCache.instance.userId)?.trim() ?? '';
      if (uidOptimistic.isNotEmpty) {
        unawaited(
          SelfReviewLikeLocalPrefs.instance.setBoost(
            uidOptimistic,
            serverSnap.id,
            _selfLikeLocalBoost,
          ),
        );
      }
    } else {
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
      nonOwnLikeOptimisticRow = _currentReview;
    }

    final previousLikeStatus = serverSnap.isLikedByCurrentUser;
    final previousLikeCount = serverSnap.likeCount;

    try {
      // Get token (session already exists via cookies)
      final firebaseIdToken = await _sessionHelper.getTokenAndSetHeader();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Toggle and confirm with actual server response
      final newLikeStatus = await _interactionRepository.toggleReviewLike(
        firebaseIdToken,
        serverSnap.id,
      );

      final uid =
          (_viewerUserId ?? CurrentUserCache.instance.userId)?.trim() ?? '';
      if (uid.isNotEmpty && _isOwnReview) {
        unawaited(
          SelfReviewLikeLocalPrefs.instance.setBoost(
            uid,
            serverSnap.id,
            newLikeStatus,
          ),
        );
      }

      setState(() {
        if (_isOwnReview) {
          _selfLikeLocalBoost = false;
          final base = serverSnap;
          _currentReview = ReviewDto(
            id: base.id,
            title: base.title,
            description: base.description,
            isCollaborative: base.isCollaborative,
            rating: base.rating,
            createdAt: base.createdAt,
            productId: base.productId,
            productName: base.productName,
            ownerId: base.ownerId,
            ownerUserName: base.ownerUserName,
            ownerProfilePhotoUrl: base.ownerProfilePhotoUrl,
            mediaList: base.mediaList,
            likeCount:
                newLikeStatus
                    ? (previousLikeCount + 1)
                    : (previousLikeCount > 0 ? previousLikeCount - 1 : 0),
            isLikedByCurrentUser: newLikeStatus,
            isProductNotListed: base.isProductNotListed,
            isReviewInactive: base.isReviewInactive,
          );
        } else {
          final opt = nonOwnLikeOptimisticRow ?? _currentReview;
          final nextCount =
              newLikeStatus == opt.isLikedByCurrentUser
                  ? opt.likeCount
                  : (newLikeStatus
                      ? (serverSnap.likeCount + 1)
                      : (serverSnap.likeCount > 0
                          ? serverSnap.likeCount - 1
                          : 0));
          _currentReview = ReviewDto(
            id: opt.id,
            title: opt.title,
            description: opt.description,
            isCollaborative: opt.isCollaborative,
            rating: opt.rating,
            createdAt: opt.createdAt,
            productId: opt.productId,
            productName: opt.productName,
            ownerId: opt.ownerId,
            ownerUserName: opt.ownerUserName,
            ownerProfilePhotoUrl: opt.ownerProfilePhotoUrl,
            mediaList: opt.mediaList,
            likeCount: nextCount,
            isLikedByCurrentUser: newLikeStatus,
            isProductNotListed: opt.isProductNotListed,
            isReviewInactive: opt.isReviewInactive,
          );
        }
      });
    } catch (e) {
      if (_isOwnReview &&
          interactionErrorLooksLikeCannotLikeOwnReview(e)) {
        final uid =
            (_viewerUserId ?? CurrentUserCache.instance.userId)?.trim() ?? '';
        if (uid.isNotEmpty) {
          await SelfReviewLikeLocalPrefs.instance.setBoost(
            uid,
            serverSnap.id,
            _selfLikeLocalBoost,
          );
        }
      } else if (_isOwnReview) {
        final uid =
            (_viewerUserId ?? CurrentUserCache.instance.userId)?.trim() ?? '';
        if (uid.isNotEmpty) {
          await SelfReviewLikeLocalPrefs.instance.setBoost(
            uid,
            serverSnap.id,
            boostBeforeTap,
          );
        }
        if (mounted) {
          setState(() => _selfLikeLocalBoost = boostBeforeTap);
        }
        if (mounted) {
          final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
          CustomSnackBar.show(
            context,
            message: errorMessage,
            variant: CustomSnackBarVariant.error,
          );
        }
      } else {
        setState(() {
          _currentReview = ReviewDto(
            id: serverSnap.id,
            title: serverSnap.title,
            description: serverSnap.description,
            isCollaborative: serverSnap.isCollaborative,
            rating: serverSnap.rating,
            createdAt: serverSnap.createdAt,
            productId: serverSnap.productId,
            productName: serverSnap.productName,
            ownerId: serverSnap.ownerId,
            ownerUserName: serverSnap.ownerUserName,
            ownerProfilePhotoUrl: serverSnap.ownerProfilePhotoUrl,
            mediaList: serverSnap.mediaList,
            likeCount: previousLikeCount,
            isLikedByCurrentUser: previousLikeStatus,
            isProductNotListed: serverSnap.isProductNotListed,
            isReviewInactive: serverSnap.isReviewInactive,
          );
        });

        if (mounted) {
          final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
          CustomSnackBar.show(
            context,
            message: errorMessage,
            variant: CustomSnackBarVariant.error,
          );
        }
      }
    } finally {
      _reviewDetailPollBarrierEpoch++;
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

  BoxDecoration _shellCardDecoration() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.bodySecondary.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: AppColors.textSecondary,
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
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFEBECEF)),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: AppColors.textPrimary.withValues(alpha: 0.85),
          ),
          onPressed: () {
            Navigator.pop(context, true);
          },
        ),
        title: Text(
          'Review details',
          style: AppTextStyles.heading2.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_canShowChatIcon)
            IconButton(
              icon: Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.textPrimary.withValues(alpha: 0.85),
              ),
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
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _openOwnerProfile,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: _shellCardDecoration(),
                                  child: Row(
                                    children: [
                                      ProfileAvatarImage(
                                        size: 52,
                                        imageUrl:
                                            _currentReview.ownerProfilePhotoUrl,
                                        fallbackInitial:
                                            _currentReview.ownerUserName,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    '@${_currentReview.ownerUserName}',
                                                    style: AppTextStyles
                                                        .productTitle
                                                        .copyWith(fontSize: 16),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (_currentReview
                                                    .isCollaborative) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary
                                                          .withValues(
                                                        alpha: 0.1,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        8,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'Sponsored',
                                                      style: AppTextStyles.chip
                                                          .copyWith(
                                                        color:
                                                            AppColors.primary,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _formatDate(
                                                _currentReview.createdAt,
                                              ),
                                              style: AppTextStyles.bodySmall
                                                  .copyWith(
                                                color: AppColors.textSecondary,
                                                height: 1.3,
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
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                              decoration: _shellCardDecoration(),
                              child: Row(
                                children: [
                                  ...List.generate(5, (index) {
                                    final filled =
                                        index < _currentReview.rating;
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        right: index < 4 ? 4 : 0,
                                      ),
                                      child: Icon(
                                        filled
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        size: 28,
                                        color: filled
                                            ? _starFilled
                                            : _starEmpty,
                                      ),
                                    );
                                  }),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${_currentReview.rating}.0',
                                    style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _onProductCardTap,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: _shellCardDecoration(),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Image.network(
                                          _currentProduct.imageURL,
                                          width: 88,
                                          height: 88,
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return Container(
                                              width: 88,
                                              height: 88,
                                              color: _fieldFill,
                                              child: const Icon(
                                                Icons.image_not_supported_outlined,
                                                color: AppColors.textSecondary,
                                                size: 32,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _currentProduct.name,
                                              style: AppTextStyles.productTitle
                                                  .copyWith(
                                                fontSize: 16,
                                                height: 1.25,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (_currentProduct.description !=
                                                    null &&
                                                _currentProduct
                                                    .description!
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                _currentProduct.description!,
                                                style: AppTextStyles.body
                                                    .copyWith(
                                                  color:
                                                      AppColors.textSecondary,
                                                  height: 1.35,
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
                                            .withValues(alpha: 0.45),
                                        size: 26,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (_currentReview.mediaList.isNotEmpty) ...[
                              _sectionLabel('Review photos'),
                              const SizedBox(height: 4),
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

                                    // Aynı origin / göreli veya Bearer isteyen URL’ler: Image.network 401 verir.
                                    if (_usePlainNetworkImageFor(media)) {
                                      final u = (media.url ?? '').trim();
                                      if (u.isNotEmpty) {
                                        return GestureDetector(
                                          onTap: () => _openMediaPreview(u),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.network(
                                              u,
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
                                                    color: AppColors
                                                        .textSecondary
                                                        .withValues(alpha: 0.1),
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
                                      final i = (media.imageUrl ?? '').trim();
                                      return GestureDetector(
                                        onTap: () => _openMediaPreview(i),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.network(
                                            i,
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
                                                      .withValues(alpha: 0.1),
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

                                    final fetchUrl =
                                        _authenticatedFetchUrlFor(media);
                                    final mediaFutureKey = _mediaFutureKey(media);
                                    return FutureBuilder<Uint8List?>(
                                      future:
                                          _mediaFutures[mediaFutureKey] ??
                                          (_mediaFutures[mediaFutureKey] =
                                              _loadMediaImage(fetchUrl)),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return Container(
                                            width: 120,
                                            height: 120,
                                            decoration: BoxDecoration(
                                              color: AppColors.textSecondary
                                                  .withValues(alpha: 0.1),
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
                                                  .withValues(alpha: 0.1),
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
                                                      .withValues(alpha: 0.1),
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
                              const SizedBox(height: 20),
                            ] else ...[
                              _sectionLabel('Review photos'),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 22,
                                  horizontal: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: _fieldFill,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.border.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.hide_image_outlined,
                                      color: AppColors.textSecondary
                                          .withValues(alpha: 0.85),
                                      size: 26,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        'No images uploaded',
                                        style: AppTextStyles.body.copyWith(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            _sectionLabel('Review'),
                            const SizedBox(height: 4),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: _shellCardDecoration(),
                              child: Text(
                                _currentReview.description ??
                                    _currentReview.title,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 15,
                                  height: 1.5,
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
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    const barH = 48.0;
    final likeStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      minimumSize: const Size(0, barH),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final updateStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      side: BorderSide(
        color: AppColors.primary.withValues(alpha: 0.45),
        width: 1.2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, barH),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final deleteStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.textSecondary,
      side: BorderSide(
        color: AppColors.border.withValues(alpha: 0.85),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, barH),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.border.withValues(alpha: 0.4),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              10,
              10,
              10,
              (keyboard > 0 ? keyboard : bottomSafe) + 8,
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
                              _reviewForLikeBar.isLikedByCurrentUser
                                  ? Icons.thumb_up_rounded
                                  : Icons.thumb_up_alt_outlined,
                              size: 20,
                              color:
                                  _reviewForLikeBar.isLikedByCurrentUser
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                            ),
                            label: Text(
                              '${_reviewForLikeBar.likeCount}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                color:
                                    _reviewForLikeBar.isLikedByCurrentUser
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openEditReview,
                            style: updateStyle,
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            label: Text(
                              'Update',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _onDeleteReview,
                            style: deleteStyle,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            label: Text(
                              'Delete',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
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
                              _reviewForLikeBar.isLikedByCurrentUser
                                  ? Icons.thumb_up_rounded
                                  : Icons.thumb_up_alt_outlined,
                              size: 20,
                              color:
                                  _reviewForLikeBar.isLikedByCurrentUser
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                            ),
                            label: Text(
                              '${_reviewForLikeBar.likeCount}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                color:
                                    _reviewForLikeBar.isLikedByCurrentUser
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
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
                              ReviewReportStorage.hasReportedSync(
                                    _currentReview.id,
                                  )
                                  ? Icons.flag_rounded
                                  : Icons.flag_outlined,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            label: Text(
                              'Report',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
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

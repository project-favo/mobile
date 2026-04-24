import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/config/app_background_timers.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/utils/exceptions.dart';
import '../../../../../core/utils/product_listing_flags.dart';
import '../../../../../core/utils/entity_active.dart';
import '../../../../../core/utils/content_availability_messages.dart';
import '../../../../../core/utils/content_unavailable_dialog.dart';
import '../../../../../core/utils/product_report_storage.dart';
import '../../../../../core/utils/review_report_storage.dart';
import '../../../../../core/utils/app_datetime.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/cache/product_memory_cache.dart';
import '../../../../../core/utils/resolve_media_url.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../routes/app_routes.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/user_response_dto.dart';
import '../../../data/models/tag_dto.dart';
import '../../../data/models/conversation_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../messages/chat_detail_page.dart';
import '../../review/pages/review_detail_page.dart';
import 'follow_list_page.dart';
import '../widgets/profile_review_row_card.dart';
import '../../home_page.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;
  final String userName;
  final String? profileImageUrl;
  /// [prefillUser] + [prefillProfileImage] ikisi birden doluysa tekrar kullanıcı/yüz API’si yok.
  final UserResponseDto? prefillUser;
  final UserProfileImageFetch? prefillProfileImage;

  const UserProfilePage({
    super.key,
    required this.userId,
    required this.userName,
    this.profileImageUrl,
    this.prefillUser,
    this.prefillProfileImage,
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
  final Set<String> _unlistedProductIdsFromFailedFetch = {};
  final Set<String> _productIdsReportedByMeFromServer = {};
  final Set<String> _reviewProductIdsNotOnHomeFirstPage = {};

  Timer? _otherUserProfilePollTimer;
  static const Duration _otherUserProfilePollInterval =
      AppBackgroundTimers.standardListPoll;
  bool _otherUserProfilePollInFlight = false;
  /// Hedef kullanıcı yok / deaktif; [HomePage]'e dönüldü.
  bool _exitedBecauseUserGone = false;

  late TabController _tabController;
  String _selectedDateSort = 'Newest';

  bool _isFollowing = false;
  bool _isFollowLoading = false;
  int _followerCount = 0;
  int _followingCount = 0;
  List<ReviewDto> _reviews = [];
  bool _isLoadingReviews = true;
  bool _isLoadingCounts = true;
  /// Backend hesabı kapatılmış; içerik ve etkileşim gösterme.
  bool _profileUnavailable = false;
  /// Görünen profil fotoğrafı (parametre veya yorum listesinden)
  String? _avatarImageUrl;
  Uint8List? _avatarMemoryBytes;
  String? _avatarPhotoDataRaw;
  String _profileUsername = '';
  String? _profileFullName;
  bool _profileAnonymous = false;

  @override
  void initState() {
    super.initState();
    unawaited(ReviewReportStorage.hydrateForCurrentUser());
    unawaited(ProductReportStorage.hydrateForCurrentUser());
    _tabController = TabController(length: 1, vsync: this);
    _avatarImageUrl = widget.profileImageUrl;
    _profileUsername = widget.userName.trim();
    _start();
  }

  void _applyIdentityFromUser(UserResponseDto u) {
    final uname = u.userName.trim();
    final name = (u.name ?? '').trim();
    final surname = (u.surname ?? '').trim();
    final fullName = [name, surname].where((e) => e.isNotEmpty).join(' ').trim();
    setState(() {
      if (uname.isNotEmpty) {
        _profileUsername = uname;
      }
      _profileAnonymous = u.profileAnonymous;
      _profileFullName = fullName.isNotEmpty ? fullName : null;
    });
  }

  String _maskedProfileFullName() {
    final full = (_profileFullName ?? '').trim();
    final userName = _profileUsername.trim();
    String maskPart(String p) {
      final t = p.trim();
      if (t.isEmpty) return '';
      return '${t[0].toUpperCase()}****';
    }

    if (full.isNotEmpty) {
      final parts = full
          .split(RegExp(r'\s+'))
          .where((p) => p.trim().isNotEmpty)
          .toList();
      if (parts.length == 1) return maskPart(parts.first);
      return '${maskPart(parts.first)} ${maskPart(parts.last)}';
    }

    if (userName.isNotEmpty) {
      final unameParts = userName
          .split(RegExp(r'[\s._-]+'))
          .where((p) => p.trim().isNotEmpty)
          .toList();
      if (unameParts.length >= 2) {
        return '${maskPart(unameParts.first)} ${maskPart(unameParts.last)}';
      }
      return maskPart(userName);
    }

    return 'U****';
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
    } on DeactivatedAccountException {
      return;
    } catch (_) {}
    if (!mounted) return;
    UserResponseDto? preloaded = widget.prefillUser;
    UserProfileImageFetch? prefillImg = widget.prefillProfileImage;
    String? preSession;
    final wid = widget.userId.trim();
    if (wid.isEmpty) {
      if (mounted) _exitToHomeBecauseUserUnavailable();
      return;
    }
    Future<UserResponseDto?> uFuture() async {
      try {
        return await _authService.getUserById(wid);
      } on TargetUserNotAvailableException {
        rethrow;
      } catch (_) {
        return null;
      }
    }

    if (preloaded != null && prefillImg != null) {
      preSession = await _sessionHelper.ensureSession();
    } else if (preloaded != null) {
      try {
        preSession = await _sessionHelper.ensureSession();
        if (!mounted) return;
        prefillImg = await _authService.fetchUserProfileImage(wid);
      } on TargetUserNotAvailableException {
        if (mounted) _exitToHomeBecauseUserUnavailable();
        return;
      } catch (_) {
        preSession = await _sessionHelper.ensureSession();
        try {
          prefillImg = await _authService.fetchUserProfileImage(wid);
        } catch (_) {}
      }
    } else {
      try {
        final trip = await Future.wait<dynamic>([
          _sessionHelper.ensureSession(),
          uFuture(),
          _authService.fetchUserProfileImage(wid),
        ]);
        preSession = trip[0] as String?;
        preloaded = trip[1] as UserResponseDto?;
        prefillImg = trip[2] as UserProfileImageFetch?;
      } on TargetUserNotAvailableException {
        if (mounted) _exitToHomeBecauseUserUnavailable();
        return;
      } catch (_) {
        preSession = await _sessionHelper.ensureSession();
        try {
          preloaded = await _authService.getUserById(wid);
        } on TargetUserNotAvailableException {
          if (mounted) _exitToHomeBecauseUserUnavailable();
          return;
        } catch (_) {}
        prefillImg = await _authService.fetchUserProfileImage(wid);
      }
    }
    if (!mounted || _exitedBecauseUserGone) return;
    _applyTargetUserGate(preloaded, profileImage: prefillImg);
    if (preloaded != null) {
      _applyIdentityFromUser(preloaded);
    }
    if (!mounted || _exitedBecauseUserGone) return;
    if (prefillImg != null && prefillImg.hasImage) {
      final px = prefillImg;
      if (px.memoryBytes != null) {
        setState(() {
          _avatarMemoryBytes = px.memoryBytes;
          _avatarImageUrl = null;
          _avatarPhotoDataRaw = null;
        });
      } else if (px.imageUrl != null && px.imageUrl!.trim().isNotEmpty) {
        setState(() {
          _avatarImageUrl = px.imageUrl;
          _avatarMemoryBytes = null;
          _avatarPhotoDataRaw = null;
        });
      }
    } else if (preloaded != null) {
      final p = preloaded;
      final bytes = decodeProfilePhotoBytes(p.profilePhotoData);
      setState(() {
        final url = p.profileImageUrl?.trim();
        if (url != null && url.isNotEmpty) _avatarImageUrl = url;
        if (bytes != null && bytes.isNotEmpty) _avatarMemoryBytes = bytes;
        if (p.profilePhotoData != null && p.profilePhotoData!.trim().isNotEmpty) {
          _avatarPhotoDataRaw = p.profilePhotoData;
        }
      });
      _applyIdentityFromUser(p);
    }
    if (!mounted || _exitedBecauseUserGone) return;
    await _loadAll(sessionToken: preSession);
    if (!mounted || _exitedBecauseUserGone) return;
    if (mounted) {
      await _enrichProfileFromApi(
        preloaded,
        prefillImage: prefillImg,
        // [getUser] + [profile-image] yukarıda; tekrar istek yok, sadece yorum satırından avatar yedeği
        skipHeavyFetches: true,
      );
    }
    if (!mounted) return;
    _otherUserProfilePollTimer?.cancel();
    _otherUserProfilePollTimer = Timer.periodic(
      _otherUserProfilePollInterval,
      (_) => unawaited(_pollOtherUserProfileData()),
    );
  }

  /// 5 sn: sadece canlı sayaç/takip bilgisi; ağır review görsel yüklemelerini tetiklemez.
  Future<void> _pollOtherUserProfileData() async {
    if (!mounted) return;
    if (_exitedBecauseUserGone) return;
    if (_otherUserProfilePollInFlight) return;
    _otherUserProfilePollInFlight = true;
    await _revalidateTargetUserOrExit();
    if (!mounted || _exitedBecauseUserGone) {
      _otherUserProfilePollInFlight = false;
      return;
    }
    try {
      final token = await _sessionHelper.ensureSession();
      if (!mounted) return;
      await Future.wait<void>([
        _loadCounts(),
        _loadIsFollowing(token),
      ]);
    } catch (_) {
    } finally {
      _otherUserProfilePollInFlight = false;
    }
  }

  /// 404: [TargetUserNotAvailableException]. Askı / deaktif; [profile-image] 404 = pasif → [HomePage].
  void _applyTargetUserGate(
    UserResponseDto? u, {
    UserProfileImageFetch? profileImage,
  }) {
    if (!mounted || _exitedBecauseUserGone) return;
    if (u != null && u.isProfileViewBlocked) {
      _exitToHomeBecauseUserUnavailable();
      return;
    }
    if (profileImage != null && profileImage.isNotFound) {
      _exitToHomeBecauseUserUnavailable();
      return;
    }
  }

  Future<void> _revalidateTargetUserOrExit() async {
    if (!mounted || _exitedBecauseUserGone) return;
    final wid = widget.userId.trim();
    if (wid.isEmpty) return;
    Future<UserResponseDto?> uSafe() async {
      try {
        return await _authService.getUserById(wid);
      } on TargetUserNotAvailableException {
        rethrow;
      } catch (_) {
        return null;
      }
    }

    try {
      final w = await Future.wait<dynamic>([
        uSafe(),
        _authService.fetchUserProfileImage(wid),
      ]);
      if (!mounted) return;
      _applyTargetUserGate(
        w[0] as UserResponseDto?,
        profileImage: w[1] as UserProfileImageFetch?,
      );
    } on TargetUserNotAvailableException {
      if (mounted) _exitToHomeBecauseUserUnavailable();
    } catch (_) {}
  }

  void _exitToHomeBecauseUserUnavailable() {
    if (!mounted || _exitedBecauseUserGone) return;
    _exitedBecauseUserGone = true;
    _otherUserProfilePollTimer?.cancel();
    _otherUserProfilePollTimer = null;
    unawaited(
      showContentUnavailableDialog(
        context,
        title: kTitleUserUnavailable,
        message: kMessageUserProfileNoLongerAvailable,
        onContinue: () async {
          if (!mounted) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            await Navigator.of(context).pushAndRemoveUntil<void>(
              MaterialPageRoute<void>(builder: (_) => const HomePage()),
              (route) => false,
            );
          }
        },
      ),
    );
  }

  Future<void> _refreshProfile() async {
    if (!mounted) return;
    if (_profileUnavailable) {
      setState(() {
        _profileUnavailable = false;
        _isLoadingCounts = true;
        _isLoadingReviews = true;
      });
    }
    await _start();
  }

  Future<void> _enrichProfileFromApi(
    UserResponseDto? preloaded, {
    UserProfileImageFetch? prefillImage,
    bool skipHeavyFetches = false,
  }) async {
    if (_exitedBecauseUserGone) return;
    if (skipHeavyFetches) {
      if (!mounted) return;
      final noUrl = _avatarImageUrl == null || _avatarImageUrl!.trim().isEmpty;
      final noMem = _avatarMemoryBytes == null || _avatarMemoryBytes!.isEmpty;
      if (noUrl && noMem) {
        for (final r in _reviews) {
          final photo = r.ownerProfilePhotoUrl?.trim();
          if (photo != null && photo.isNotEmpty) {
            setState(() => _avatarImageUrl = photo);
            break;
          }
        }
      }
      return;
    }
    UserResponseDto? u = preloaded;
    try {
      u ??= await _authService.getUserById(widget.userId);
      if (u != null && u.isProfileViewBlocked && mounted) {
        _exitToHomeBecauseUserUnavailable();
        return;
      }
      if (u != null && mounted) {
        final profile = u;
        final bytes = decodeProfilePhotoBytes(profile.profilePhotoData);
        setState(() {
          final url = profile.profileImageUrl?.trim();
          if (url != null && url.isNotEmpty) _avatarImageUrl = url;
          if (bytes != null && bytes.isNotEmpty) _avatarMemoryBytes = bytes;
          if (profile.profilePhotoData != null &&
              profile.profilePhotoData!.trim().isNotEmpty) {
            _avatarPhotoDataRaw = profile.profilePhotoData;
          }
        });
        _applyIdentityFromUser(profile);
      }
    } on TargetUserNotAvailableException {
      if (mounted) _exitToHomeBecauseUserUnavailable();
    } catch (_) {}
    if (!mounted) return;
    if (_exitedBecauseUserGone) return;
    // `/api/users/{id}/profile-image`: inactive → 404; [getUserById] URL sızıntısını baskıla
    var hideReviewAvatarFallback = false;
    if (prefillImage != null) {
      if (prefillImage.isNotFound) {
        if (mounted) {
          setState(() {
            _avatarImageUrl = null;
            _avatarMemoryBytes = null;
            _avatarPhotoDataRaw = null;
          });
        }
        return;
      }
      if (prefillImage.hasImage) {
        hideReviewAvatarFallback = true;
        if (mounted) {
          setState(() {
            if (prefillImage.memoryBytes != null) {
              _avatarMemoryBytes = prefillImage.memoryBytes;
              _avatarImageUrl = null;
              _avatarPhotoDataRaw = null;
            } else {
              _avatarImageUrl = prefillImage.imageUrl;
              _avatarMemoryBytes = null;
              _avatarPhotoDataRaw = null;
            }
          });
        }
        if (!mounted) return;
        return;
      }
    }
    if (widget.userId.trim().isNotEmpty) {
      final pix = await _authService.fetchUserProfileImage(widget.userId);
      if (!mounted) return;
      if (pix != null) {
        if (pix.isNotFound) {
          hideReviewAvatarFallback = true;
          setState(() {
            _avatarImageUrl = null;
            _avatarMemoryBytes = null;
            _avatarPhotoDataRaw = null;
          });
        } else if (pix.hasImage) {
          hideReviewAvatarFallback = true;
          setState(() {
            if (pix.memoryBytes != null) {
              _avatarMemoryBytes = pix.memoryBytes;
              _avatarImageUrl = null;
              _avatarPhotoDataRaw = null;
            } else {
              _avatarImageUrl = pix.imageUrl;
              _avatarMemoryBytes = null;
              _avatarPhotoDataRaw = null;
            }
          });
        }
      }
    }
    if (!mounted) return;
    if (hideReviewAvatarFallback) return;
    final noUrl = _avatarImageUrl == null || _avatarImageUrl!.trim().isEmpty;
    final noMem =
        _avatarMemoryBytes == null || _avatarMemoryBytes!.isEmpty;
    if (noUrl && noMem) {
      for (final r in _reviews) {
        final photo = r.ownerProfilePhotoUrl?.trim();
        if (photo != null && photo.isNotEmpty) {
          setState(() => _avatarImageUrl = photo);
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _otherUserProfilePollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll({String? sessionToken}) async {
    final token = sessionToken ?? await _sessionHelper.ensureSession();
    await Future.wait([
      _loadCounts(),
      _loadIsFollowing(token),
      _loadReviews(token),
    ]);
  }

  Future<void> _loadCounts() async {
    final results = await Future.wait([
      _interactionRepo.countVisibleFollowers(widget.userId),
      _interactionRepo.countVisibleFollowing(widget.userId),
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

  Future<void> _loadReviews(String? token, {bool background = false}) async {
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
        _unlistedProductIdsFromFailedFetch.clear();
        _productIdsReportedByMeFromServer.clear();
        _reviewProductIdsNotOnHomeFirstPage.clear();
        _avatarImageUrl = avatar;
        _isLoadingReviews = false;
      });
      _sortReviews();
      if (background) {
        return;
      }
      unawaited(_prefetchProductsForReviews(reviews));
      unawaited(_syncReportedProductFlagsFromServer());
      unawaited(_syncNotOnHomeFirstPageSet(reviews));
    } catch (_) {
      if (!mounted) return;
      if (background && _reviews.isNotEmpty) {
        return;
      }
      setState(() => _isLoadingReviews = false);
    }
  }

  void _sortReviews() {
    if (_reviews.isEmpty) return;
    final sorted = List<ReviewDto>.from(_reviews);
    sorted.sort((a, b) {
      final da = parseBackendDateTimeToLocal(a.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db = parseBackendDateTimeToLocal(b.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
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
      final unlisted = <String>[];
      final newHints = <String, ProductDto>{};
      final rows = await Future.wait(
        slice.map((id) async {
          try {
            return MapEntry(
              id,
              await _productRepository.getProductById(
                id,
                firebaseIdToken: token,
                bypassCache: false,
              ),
            );
          } on ProductNotAvailableException {
            return MapEntry<String, ProductDto?>(id, null);
          } catch (_) {
            return null;
          }
        }),
      );
      for (final e in rows) {
        if (e == null) continue;
        if (e.value == null) {
          unlisted.add(e.key);
        } else {
          newHints[e.key] = e.value!;
        }
      }
      if (mounted && (unlisted.isNotEmpty || newHints.isNotEmpty)) {
        setState(() {
          _unlistedProductIdsFromFailedFetch.addAll(unlisted);
          _reviewProductHints.addAll(newHints);
        });
      }
    }
  }

  Future<void> _syncNotOnHomeFirstPageSet(List<ReviewDto> reviews) async {
    final mine = reviews
        .map((r) => r.productId.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (mine.isEmpty) return;
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (!mounted) return;
      final feed = await _productRepository.getHomeFeed(
        page: 0,
        size: 50,
        firebaseIdToken: token,
      );
      if (!mounted) return;
      final onHome = feed.content.map((e) => e.id.trim()).toSet();
      final missing = mine.where((id) => !onHome.contains(id)).toSet();
      if (mounted) {
        setState(() {
          _reviewProductIdsNotOnHomeFirstPage
            ..clear()
            ..addAll(missing);
        });
      }
    } catch (_) {}
  }

  Future<void> _syncReportedProductFlagsFromServer() async {
    final ids = _reviews
        .map((r) => r.productId)
        .where((s) => s.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;
    final token = await _sessionHelper.getTokenAndSetHeader();
    if (token == null) return;
    final list = ids.toList();
    const inc = 5;
    final fromApi = <String>{};
    for (var i = 0; i < list.length; i += inc) {
      if (!mounted) return;
      final j = i + inc > list.length ? list.length : i + inc;
      final slice = list.sublist(i, j);
      final rows = await Future.wait(
        slice.map(
          (id) async {
            final ok = await _interactionRepo.isProductReported(token, id);
            return MapEntry(id, ok);
          },
        ),
      );
      for (final e in rows) {
        if (e.value) fromApi.add(e.key);
      }
    }
    if (mounted) {
      setState(() {
        _productIdsReportedByMeFromServer
          ..clear()
          ..addAll(fromApi);
      });
    }
  }

  /// Askı/404 gibi sinyallerle vitrin dışı ürün yorumu — liste ve istatistikte yok.
  bool _reviewRowNotListed(ReviewDto review, ProductDto? hint) {
    if (!isReviewEntityVisible(review)) return true;
    if (review.isProductNotListed) return true;
    if (hint?.isProductNotListed == true) return true;
    if (_unlistedProductIdsFromFailedFetch.contains(review.productId)) {
      return true;
    }
    if (hint != null &&
        isNotListedImpliedByEmptyProductImage(hint.imageURL)) {
      return true;
    }
    if (_reviewProductIdsNotOnHomeFirstPage.contains(review.productId) &&
        (hint == null ||
            isNotListedImpliedByEmptyProductImage(hint.imageURL))) {
      return true;
    }
    return false;
  }

  List<ReviewDto> _reviewsVisibleInProfile() {
    return _reviews.where((r) {
      final hint = _reviewProductHints[r.productId];
      return !_reviewRowNotListed(r, hint);
    }).toList();
  }

  Widget _buildUserProfileReviewsColumn() {
    final visible = _reviewsVisibleInProfile();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xLarge,
      ),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.medium),
            _buildUserProfileReviewRow(visible[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildUserProfileReviewRow(ReviewDto r) {
    final hint = _reviewProductHints[r.productId];
    return ProfileReviewRowCard(
      review: r,
      productImageUrl: hint?.imageURL,
      youReportedThisReview: ReviewReportStorage.hasReportedSync(r.id),
      youReportedThisProduct:
          ProductReportStorage.hasReportedSync(r.productId) ||
          _productIdsReportedByMeFromServer.contains(r.productId),
      onTap: () {
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
    );
  }

  String _reviewsAverageLabel() {
    final v = _reviewsVisibleInProfile();
    if (v.isEmpty) return '—';
    final sum = v.fold<double>(0, (a, r) => a + r.rating);
    return (sum / v.length).toStringAsFixed(1);
  }

  ProductDto _productForReviewDetail(ReviewDto review, ProductDto? hint) {
    if (hint != null) return hint;
    return ProductDto(
      id: review.productId,
      name: review.productName,
      imageURL: '',
      description: null,
      tag: TagDto(id: '', name: ''),
      isProductNotListed: review.isProductNotListed,
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
      setState(() => _isFollowing = nowFollowing);
      await _loadCounts();
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

  Future<void> _openFollowerList() async {
    await Navigator.push<void>(
      context,
      SlideRightRoute(
        page: FollowListPage(
          userId: widget.userId,
          title: 'Followers',
          isFollowers: true,
        ),
      ),
    );
    if (mounted) await _loadCounts();
  }

  Future<void> _openFollowingList() async {
    await Navigator.push<void>(
      context,
      SlideRightRoute(
        page: FollowListPage(
          userId: widget.userId,
          title: 'Following',
          isFollowers: false,
        ),
      ),
    );
    if (mounted) await _loadCounts();
  }

  @override
  Widget build(BuildContext context) {
    if (_exitedBecauseUserGone) {
      return const Scaffold(
        body: SizedBox.shrink(),
      );
    }
    final handle = '@${_profileUsername.toLowerCase().replaceAll(' ', '')}';
    final displayName = _profileAnonymous
        ? _maskedProfileFullName()
        : (_profileFullName ?? _profileUsername);
    final canOpenMessage = !_profileUnavailable && int.tryParse(widget.userId) != null;

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
          if (canOpenMessage)
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
        onRefresh: _refreshProfile,
        child: _profileUnavailable
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  const Icon(
                    Icons.person_off_outlined,
                    size: 56,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xLarge,
                    ),
                    child: Text(
                      'This profile is not available.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium,
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xxLarge),
              ProfileAvatar(
                radius: 50,
                imageUrl: _avatarImageUrl ?? widget.profileImageUrl,
                memoryBytes: _avatarMemoryBytes,
                fallbackInitial: _profileUsername,
              ),
              const SizedBox(height: AppSpacing.large),
              Text(
                displayName,
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
                              onTap: () => unawaited(_openFollowerList()),
                              child: _StatItem(
                                count: _followerCount,
                                label: 'Followers',
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => unawaited(_openFollowingList()),
                              child: _StatItem(
                                count: _followingCount,
                                label: 'Following',
                              ),
                            ),
                          ),
                          Expanded(
                            child: _StatItem(
                              count: _isLoadingReviews
                                  ? 0
                                  : _reviewsVisibleInProfile().length,
                              label: 'Reviews',
                            ),
                          ),
                          Expanded(
                            child: Tooltip(
                              message:
                                  'Average star rating of this user’s reviews (out of 5).',
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
              else if (_reviewsVisibleInProfile().isEmpty)
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
                _buildUserProfileReviewsColumn(),
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

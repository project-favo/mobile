import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slide_to_act/slide_to_act.dart';
import '../../../../../core/config/api_config.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/repositories/review_repository.dart';

class AddReviewPage extends StatefulWidget {
  final ProductDto product;

  /// Doluysa [PUT /api/reviews/{id}] ile güncelleme modu
  final ReviewDto? reviewToEdit;

  const AddReviewPage({super.key, required this.product, this.reviewToEdit});

  @override
  State<AddReviewPage> createState() => _AddReviewPageState();
}

class _AddReviewPageState extends State<AddReviewPage> {
  final GlobalKey<SlideActionState> _slideActionKey =
      GlobalKey<SlideActionState>();

  static const Color _pageBackground = Color(0xFFF4F5F7);
  static const Color _fieldFill = Color(0xFFF9FAFB);
  static const Color _starEmpty = Color(0xFFD1D5DB);
  static const Color _starFilled = Color(0xFFF5A623);

  final ReviewRepository _reviewRepository = ReviewRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final TextEditingController _reviewController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int _selectedRating = 0;
  bool _isCollaborative = false;
  final int _maxCharacters = 500;
  static const int _minReviewLength = 10;
  static const int _maxReviewPhotos = 5;
  final ImagePicker _imagePicker = ImagePicker();
  final List<XFile> _selectedImages = [];

  /// Düzenleme modunda sunucuda kalan görseller (silinenler listeden çıkar; PUT’ta `id` ile korunur).
  List<ReviewMediaDto> _existingMedia = [];
  Map<String, String>? _imageHeaders;

  bool get _isEditMode => widget.reviewToEdit != null;

  /// Yıldız + metin (validator ile aynı kurallar); kaydır butonu yalnızca buna göre etkin.
  bool get _canSlideToSubmit {
    if (_selectedRating < 1) return false;
    final t = _reviewController.text.trim();
    if (t.isEmpty || t.length < _minReviewLength) return false;
    return true;
  }

  bool get _hasAnyPhotos =>
      _existingMedia.isNotEmpty || _selectedImages.isNotEmpty;

  int get _photoCount => _existingMedia.length + _selectedImages.length;

  bool get _canAddMorePhotos => _photoCount < _maxReviewPhotos;

  void _showPhotoLimitSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('You can add up to $_maxReviewPhotos photos.'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _applyReviewToForm(ReviewDto r) {
    final d = r.description?.trim();
    final t = r.title.trim();
    final body = (d != null && d.isNotEmpty) ? d : (t.isNotEmpty ? t : '');
    _reviewController.text = body;
    final rt = r.rating;
    _selectedRating = rt >= 1 && rt <= 5 ? rt : 0;
    _isCollaborative = r.isCollaborative;
  }

  @override
  void initState() {
    super.initState();
    final r = widget.reviewToEdit;
    if (r != null) {
      _existingMedia = List<ReviewMediaDto>.from(r.mediaList);
      _applyReviewToForm(r);
    }
    _reviewController.addListener(() {
      setState(() {}); // Character count için
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshImageAuthHeaders());
    });
  }

  Future<void> _refreshImageAuthHeaders() async {
    final t = await _sessionHelper.ensureSession();
    if (!mounted) return;
    setState(() {
      _imageHeaders = t != null ? {'Authorization': 'Bearer $t'} : null;
    });
  }

  @override
  void didUpdateWidget(covariant AddReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final n = widget.reviewToEdit;
    final o = oldWidget.reviewToEdit;
    if (n != null && (o == null || o.id != n.id)) {
      _existingMedia = List<ReviewMediaDto>.from(n.mediaList);
      _applyReviewToForm(n);
      unawaited(_refreshImageAuthHeaders());
      setState(() {});
    }
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (!_canAddMorePhotos) {
      _showPhotoLimitSnackBar();
      return;
    }
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85, // Kaliteyi biraz düşürerek dosya boyutunu küçült
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image != null) {
        if (!mounted) return;
        if (_photoCount >= _maxReviewPhotos) return;
        setState(() {
          _selectedImages.add(image);
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: ${e.toString()}');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _removeExistingMedia(int index) {
    if (index < 0 || index >= _existingMedia.length) return;
    setState(() {
      _existingMedia.removeAt(index);
    });
  }

  bool _mediaCompositionChanged() {
    final initial = widget.reviewToEdit;
    if (initial == null) return false;
    if (_selectedImages.isNotEmpty) return true;
    final a = initial.mediaList.map((m) => m.id).toSet();
    final b = _existingMedia.map((m) => m.id).toSet();
    return a.length != b.length || !a.containsAll(b) || !b.containsAll(a);
  }

  /// Güncelleme: önce korunacak mevcut id’ler, ardından yeni dosya baytları.
  Future<List<ReviewMediaRequestDto>> _buildUpdateMediaPayload() async {
    final kept = <ReviewMediaRequestDto>[];
    for (final m in _existingMedia) {
      final id = m.id.trim();
      if (id.isNotEmpty) {
        kept.add(ReviewMediaRequestDto.retain(existingMediaId: id));
      }
    }
    final uploads = await _convertImagesToMediaList();
    return [...kept, ...uploads];
  }

  void _showImageSourceDialog() {
    if (!_canAddMorePhotos) {
      _showPhotoLimitSnackBar();
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.photo_library,
                    color: AppColors.primary,
                  ),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt,
                    color: AppColors.primary,
                  ),
                  title: const Text('Take a Photo'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  Future<List<ReviewMediaRequestDto>> _convertImagesToMediaList() async {
    final List<ReviewMediaRequestDto> mediaList = [];

    for (final imageFile in _selectedImages) {
      try {
        final file = File(imageFile.path);
        final bytes = await file.readAsBytes();
        final mimeType = imageFile.mimeType ?? 'image/jpeg';

        mediaList.add(
          ReviewMediaRequestDto.upload(imageData: bytes, mimeType: mimeType),
        );
      } catch (e) {
        if (kDebugMode)
          debugPrint('Error converting image ${imageFile.path}: $e');
      }
    }

    return mediaList;
  }

  BoxDecoration _cardDecoration() {
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

  Widget _sectionLabel(String text, {double bottomPadding = 10}) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
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

  /// Sunucuya gönderir. Doğrulama çağırmadan önce yapılmalıdır. Başarıda `true`.
  Future<bool> _submitReviewInternal() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated. Please login first.');
      }

      final firebaseIdToken = await _sessionHelper.ensureSession();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      List<ReviewMediaRequestDto>? mediaList;
      if (widget.reviewToEdit != null) {
        if (_mediaCompositionChanged()) {
          mediaList = await _buildUpdateMediaPayload();
        }
      } else if (_selectedImages.isNotEmpty) {
        mediaList = await _convertImagesToMediaList();
      }

      final text = _reviewController.text;
      if (widget.reviewToEdit != null) {
        final request = UpdateReviewRequestDto(
          title: text.length > 50 ? text.substring(0, 50) : text,
          description: text,
          isCollaborative: _isCollaborative,
          rating: _selectedRating,
          mediaList: mediaList,
        );
        await _reviewRepository.updateReview(
          firebaseIdToken,
          widget.reviewToEdit!.id,
          request,
        );
      } else {
        final request = CreateReviewRequestDto(
          productId: widget.product.id,
          title: text.length > 50 ? text.substring(0, 50) : text,
          description: text,
          isCollaborative: _isCollaborative,
          rating: _selectedRating,
          mediaList: mediaList,
        );
        await _reviewRepository.createReview(firebaseIdToken, request);
      }

      return true;
    } catch (e) {
      final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
      _showErrorSnackBar(errorMessage);
      return false;
    }
  }

  /// slide_to_act: paket animasyon bittikten sonra çağırır; bitince kendi `reset()`’ini de await eder.
  Future<void> _onSlideSubmit() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Please fix the errors above');
      return;
    }
    if (_selectedRating == 0) {
      _showErrorSnackBar('Please select a rating');
      return;
    }

    final ok = await _submitReviewInternal();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Klavye: Scaffold resizeToAvoidBottomInset ile gövde zaten yukarı kayar;
    // viewInsets.bottom'u tekrar alt bar + scroll padding'e eklemek taşmaya yol açar.
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.surface,
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditMode ? 'Edit review' : 'Add a review',
          style: AppTextStyles.heading2.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: SizedBox.expand(
            child: ColoredBox(
              color: _pageBackground,
              child: Align(
                alignment: Alignment.topCenter,
                child: ListView(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      // Product — compact
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: _cardDecoration(),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                widget.product.imageURL,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 64,
                                    height: 64,
                                    color: _fieldFill,
                                    child: const Icon(
                                      Icons.image_not_supported_outlined,
                                      color: AppColors.textSecondary,
                                      size: 28,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.product.name,
                                    style: AppTextStyles.productTitle.copyWith(
                                      fontSize: 14,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if ((widget.product.description ?? '')
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.product.description ?? '',
                                      style: AppTextStyles.body.copyWith(
                                        color: AppColors.textSecondary,
                                        height: 1.3,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Rating + review + photos (tek kart — daha az kaydırma)
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                        decoration: _cardDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionLabel('Rating', bottomPadding: 6),
                            Row(
                              children: List.generate(5, (index) {
                                final filled = index < _selectedRating;
                                return Expanded(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedRating = index + 1;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: Center(
                                          child: Icon(
                                            filled
                                                ? Icons.star_rounded
                                                : Icons.star_outline_rounded,
                                            size: 30,
                                            color:
                                                filled
                                                    ? _starFilled
                                                    : _starEmpty,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 8),
                            Divider(
                              height: 1,
                              color: AppColors.border.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 8),
                            _sectionLabel('Your review', bottomPadding: 6),
                            TextFormField(
                              controller: _reviewController,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: _maxCharacters,
                              scrollPadding: EdgeInsets.only(
                                bottom: bottomSafe + 180,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Share your thoughts about this product…',
                                hintStyle: AppTextStyles.body.copyWith(
                                  color: AppColors.hint,
                                ),
                                contentPadding: const EdgeInsets.all(12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: AppColors.border.withValues(
                                      alpha: 0.65,
                                    ),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: _fieldFill,
                                counterText:
                                    '${_reviewController.text.length} / $_maxCharacters',
                                counterStyle: AppTextStyles.bodySecondary
                                    .copyWith(fontSize: 11),
                              ),
                              style: AppTextStyles.body.copyWith(height: 1.45),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please write a review';
                                }
                                if (value.trim().length < _minReviewLength) {
                                  return 'Review must be at least $_minReviewLength characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 6),
                            Divider(
                              height: 1,
                              color: AppColors.border.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: _sectionLabel(
                                    'Photos (optional)',
                                    bottomPadding: 4,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '$_photoCount / $_maxReviewPhotos',
                                    style: AppTextStyles.bodySecondary.copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_hasAnyPhotos) ...[
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 72,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount:
                                      _existingMedia.length +
                                      _selectedImages.length,
                                  itemBuilder: (context, index) {
                                    if (index < _existingMedia.length) {
                                      final m = _existingMedia[index];
                                      final u = m.getMediaUrl(
                                        ApiConfig.baseUrl,
                                      );
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Image.network(
                                                u,
                                                width: 72,
                                                height: 72,
                                                fit: BoxFit.cover,
                                                headers: _imageHeaders,
                                                gaplessPlayback: true,
                                                errorBuilder: (context, e, __) {
                                                  return Container(
                                                    width: 72,
                                                    height: 72,
                                                    color: _fieldFill,
                                                    child: const Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                      color:
                                                          AppColors
                                                              .textSecondary,
                                                      size: 28,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap:
                                                      () =>
                                                          _removeExistingMedia(
                                                            index,
                                                          ),
                                                  customBorder:
                                                      const CircleBorder(),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(5),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.55,
                                                          ),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.close_rounded,
                                                      color: Colors.white,
                                                      size: 14,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    final fileIndex =
                                        index - _existingMedia.length;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Image.file(
                                              File(
                                                _selectedImages[fileIndex].path,
                                              ),
                                              width: 72,
                                              height: 72,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap:
                                                    () =>
                                                        _removeImage(fileIndex),
                                                customBorder:
                                                    const CircleBorder(),
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.55,
                                                        ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.close_rounded,
                                                    color: Colors.white,
                                                    size: 14,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Opacity(
                              opacity: _canAddMorePhotos ? 1 : 0.45,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    if (!_canAddMorePhotos) {
                                      _showPhotoLimitSnackBar();
                                      return;
                                    }
                                    _showImageSourceDialog();
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.border.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 12,
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            !_hasAnyPhotos
                                                ? Icons
                                                    .add_photo_alternate_outlined
                                                : Icons.add_rounded,
                                            size: 28,
                                            color: AppColors.textSecondary,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            !_hasAnyPhotos
                                                ? 'Tap to add photos'
                                                : 'Add more photos',
                                            style: AppTextStyles.body.copyWith(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            _canAddMorePhotos
                                                ? 'Max $_maxReviewPhotos images · JPG or PNG'
                                                : 'Maximum $_maxReviewPhotos photos',
                                            textAlign: TextAlign.center,
                                            style: AppTextStyles.bodySecondary
                                                .copyWith(fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Disclosure
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: _cardDecoration(),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Collaborative / sponsored',
                                    style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Turn on if this review is sponsored or co-created.',
                                    style: AppTextStyles.bodySecondary.copyWith(
                                      fontSize: 12,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isCollaborative,
                              onChanged: (value) {
                                setState(() {
                                  _isCollaborative = value;
                                });
                              },
                              activeThumbColor: AppColors.surface,
                              activeTrackColor: AppColors.primary,
                              inactiveThumbColor: const Color(0xFF9CA3AF),
                              inactiveTrackColor: const Color(0xFFE5E7EB),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: ColoredBox(
        color: AppColors.surface,
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.border.withValues(alpha: 0.4),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Opacity(
                  opacity: _canSlideToSubmit ? 1 : 0.5,
                  child: SlideAction(
                    key: _slideActionKey,
                    enabled: _canSlideToSubmit,
                    height: 56,
                    borderRadius: 28,
                    elevation: 1,
                    animationDuration: const Duration(
                      milliseconds: 280,
                    ),
                    innerColor: scheme.onPrimary,
                    outerColor: scheme.primary,
                    text: _isEditMode
                        ? 'Slide to update review'
                        : 'Slide to post review',
                    textStyle: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                    textColor: scheme.onPrimary,
                    sliderRotate: false,
                    sliderButtonIconPadding: 12,
                    sliderButtonIconSize: 22,
                    sliderButtonIcon: const Icon(
                      Icons.arrow_forward,
                      color: Colors.black,
                    ),
                    alignment: Alignment.center,
                    onSubmit: () async {
                      try {
                        await _onSlideSubmit();
                      } catch (e, st) {
                        if (kDebugMode) {
                          debugPrint('Slide submit error: $e\n$st');
                        }
                        if (!mounted) return;
                        _slideActionKey.currentState?.reset();
                        _showErrorSnackBar(
                          ErrorHandler.getUserFriendlyMessage(e),
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

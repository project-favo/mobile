import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/repositories/review_repository.dart';

class AddReviewPage extends StatefulWidget {
  final ProductDto product;

  const AddReviewPage({super.key, required this.product});

  @override
  State<AddReviewPage> createState() => _AddReviewPageState();
}

class _AddReviewPageState extends State<AddReviewPage> {
  final ReviewRepository _reviewRepository = ReviewRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final TextEditingController _reviewController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  int _selectedRating = 0;
  bool _isCollaborative = false;
  bool _isLoading = false;
  final int _maxCharacters = 500;
  final ImagePicker _imagePicker = ImagePicker();
  List<XFile> _selectedImages = [];

  @override
  void initState() {
    super.initState();
    _reviewController.addListener(() {
      setState(() {}); // Character count için
    });
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85, // Kaliteyi biraz düşürerek dosya boyutunu küçült
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image != null) {
        setState(() {
          _selectedImages.add(image);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
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
          ReviewMediaRequestDto(
            imageData: bytes,
            mimeType: mimeType,
          ),
        );
      } catch (e) {
        print('Error converting image ${imageFile.path}: $e');
        // Hata olsa bile devam et, diğer fotoğrafları yükle
      }
    }

    return mediaList;
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 48,
                  ),
                ),
                const SizedBox(height: AppSpacing.xLarge),
                
                // Success Title
                Text(
                  'Review Posted!',
                  style: AppTextStyles.heading2.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.medium),
                
                // Success Message
                Text(
                  'Your review has been successfully posted and is now visible to other users.',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xLarge),
                
                // OK Button
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    text: 'OK',
                    onPressed: () {
                      Navigator.of(context).pop(); // Dialog'u kapat
                      Navigator.pop(context, true); // AddReviewPage'i kapat ve true döndür
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitReview() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated. Please login first.');
      }

      // Ensure session and get token
      final firebaseIdToken = await _sessionHelper.ensureSession();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Fotoğrafları media list formatına çevir
      List<ReviewMediaRequestDto>? mediaList;
      if (_selectedImages.isNotEmpty) {
        mediaList = await _convertImagesToMediaList();
      }

      // Review oluştur
      final request = CreateReviewRequestDto(
        productId: widget.product.id,
        title: _reviewController.text.length > 50
            ? _reviewController.text.substring(0, 50)
            : _reviewController.text,
        description: _reviewController.text,
        isCollaborative: _isCollaborative,
        rating: _selectedRating,
        mediaList: mediaList,
      );

      print('📝 AddReviewPage - Creating review:');
      print('   Product ID: ${widget.product.id}');
      print('   Rating: $_selectedRating');
      print('   Title: ${request.title}');
      print('   Description: ${request.description}');
      
      final createdReview = await _reviewRepository.createReview(firebaseIdToken, request);
      
      print('✅ Review created successfully:');
      print('   Review ID: ${createdReview.id}');
      print('   Rating: ${createdReview.rating}');

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add a Review',
          style: AppTextStyles.heading2,
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Information Card
              Container(
                padding: const EdgeInsets.all(AppSpacing.large),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    // Product Image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        widget.product.imageURL,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 80,
                            height: 80,
                            color: AppColors.background,
                            child: const Icon(
                              Icons.image_not_supported,
                              color: AppColors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.large),
                    // Product Name and Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product.name,
                            style: AppTextStyles.heading3,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.small),
                          Text(
                            widget.product.description ?? '',
                            style: AppTextStyles.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xLarge),

              // Star Rating Section
              Text(
                'Rating',
                style: AppTextStyles.heading3,
              ),
              const SizedBox(height: AppSpacing.medium),
              Row(
                children: List.generate(
                  5,
                  (index) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedRating = index + 1;
                        });
                      },
                      child: Icon(
                        index < _selectedRating
                            ? Icons.star
                            : Icons.star_border,
                        size: 40,
                        color: AppColors.primary,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xLarge),

              // Review Text Area
              Text(
                'Your Review',
                style: AppTextStyles.heading3,
              ),
              const SizedBox(height: AppSpacing.medium),
              TextFormField(
                controller: _reviewController,
                maxLines: 8,
                maxLength: _maxCharacters,
                decoration: InputDecoration(
                  hintText: 'Share your thoughts about this product...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  counterText: '${_reviewController.text.length} / $_maxCharacters',
                  counterStyle: AppTextStyles.bodySecondary,
                ),
                style: AppTextStyles.body,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please write a review';
                  }
                  if (value.trim().length < 10) {
                    return 'Review must be at least 10 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xLarge),

              // Collaborative / Sponsored Toggle
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.large,
                  vertical: AppSpacing.medium,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Collaborative / Sponsored',
                      style: AppTextStyles.bodyMedium,
                    ),
                    Switch(
                      value: _isCollaborative,
                      onChanged: (value) {
                        setState(() {
                          _isCollaborative = value;
                        });
                      },
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xLarge),

              // Add Photos Section
              Text(
                'Add Photos (Optional)',
                style: AppTextStyles.heading3,
              ),
              const SizedBox(height: AppSpacing.medium),
              
              // Selected Images Grid
              if (_selectedImages.isNotEmpty)
                Container(
                  height: 120,
                  margin: const EdgeInsets.only(bottom: AppSpacing.medium),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    itemBuilder: (context, index) {
                      return Container(
                        width: 120,
                        height: 120,
                        margin: const EdgeInsets.only(right: AppSpacing.medium),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.border,
                            width: 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(_selectedImages[index].path),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => _removeImage(index),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 16,
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

              // Add Photo Button
              GestureDetector(
                onTap: _showImageSourceDialog,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xxLarge),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.border,
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _selectedImages.isEmpty ? Icons.camera_alt : Icons.add_photo_alternate,
                        size: 48,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: AppSpacing.medium),
                      Text(
                        _selectedImages.isEmpty
                            ? 'Add a Photo (Optional)'
                            : 'Add More Photos',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxLarge),

              // Post Review Button
              AppButton(
                text: 'POST REVIEW',
                onPressed: _submitReview,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


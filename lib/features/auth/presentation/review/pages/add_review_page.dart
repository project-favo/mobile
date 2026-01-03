import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/repositories/auth_repository.dart';

class AddReviewPage extends StatefulWidget {
  final ProductDto product;

  const AddReviewPage({super.key, required this.product});

  @override
  State<AddReviewPage> createState() => _AddReviewPageState();
}

class _AddReviewPageState extends State<AddReviewPage> {
  final ReviewRepository _reviewRepository = ReviewRepository();
  final TextEditingController _reviewController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  int _selectedRating = 0;
  bool _isCollaborative = false;
  bool _isLoading = false;
  final int _maxCharacters = 500;

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

      // Token'ı al ve backend'e login yap (session için)
      final firebaseIdToken = await user.getIdToken(true);
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Backend session'ı kur
      try {
        final authRepository = AuthRepository();
        await authRepository.login(firebaseIdToken);
      } catch (e) {
        print('Login error: $e');
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review posted successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true); // true döndürerek ReviewPage'e güncelleme yapıldığını bildir
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post review: ${e.toString()}'),
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

              // Add a Photo (Optional)
              Container(
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
                      Icons.camera_alt,
                      size: 48,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    Text(
                      'Add a Photo (Optional)',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
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


import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/review_card.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/repositories/product_repository.dart';
import 'add_review_page.dart';

class ReviewPage extends StatefulWidget {
  final ProductDto product;

  const ReviewPage({super.key, required this.product});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final InteractionRepository _interactionRepository = InteractionRepository();
  final ReviewRepository _reviewRepository = ReviewRepository();
  final ProductRepository _productRepository = ProductRepository();
  late ProductDto _currentProduct;
  List<ReviewDto> _reviews = [];
  bool _isLoading = false;
  bool _isLoadingReviews = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.product;
    _loadReviews();
    _refreshProductData(); // Product'ı backend'den yeniden yükle (rating ve like durumu için)
  }

  /// Product'ı backend'den yeniden yükler (rating ve like durumu için)
  Future<void> _refreshProductData() async {
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

      // Product'ı tamamen yeniden yükle
      final updatedProduct = await _productRepository.getProductById(
        _currentProduct.id,
        firebaseIdToken: firebaseIdToken,
      );

      setState(() {
        _currentProduct = updatedProduct;
      });
    } catch (e) {
      print('Failed to refresh product data: $e');
    }
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoadingReviews = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Kullanıcı giriş yapmamışsa, review'ları token olmadan çekmeyi dene
        try {
          final reviews = await _reviewRepository.getReviewsByProductId(
            _currentProduct.id,
            firebaseIdToken: null,
          );
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

      // Token'ı al ve backend'e login yap (session için)
      final firebaseIdToken = await user.getIdToken(true); // Force refresh
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Backend session'ı kur (cookie'ler için)
      try {
        final authRepository = AuthRepository();
        await authRepository.login(firebaseIdToken);
      } catch (e) {
        // Login hatası olabilir ama devam edelim
        print('Login error (may be already logged in): $e');
      }

      // Review'ları çek
      final reviews = await _reviewRepository.getReviewsByProductId(
        _currentProduct.id,
        firebaseIdToken: firebaseIdToken,
      );

      setState(() {
        _reviews = reviews;
        _isLoadingReviews = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
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

    setState(() {
      _isLoading = true;
    });

    try {
      // Token'ı yenile ve backend'e login yap (session için)
      final firebaseIdToken = await user.getIdToken(true); // Force refresh
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Backend session'ı yenile
      try {
        final authRepository = AuthRepository();
        await authRepository.login(firebaseIdToken);
      } catch (e) {
        // Login hatası olabilir ama devam edelim
        print('Login error (may be already logged in): $e');
      }

      final newLikeStatus = await _interactionRepository.toggleProductLike(
        firebaseIdToken,
        _currentProduct.id,
      );

      setState(() {
        _currentProduct = ProductDto(
          id: _currentProduct.id,
          name: _currentProduct.name,
          imageURL: _currentProduct.imageURL,
          description: _currentProduct.description,
          tag: _currentProduct.tag,
          averageRating: _currentProduct.averageRating,
          isLiked: newLikeStatus,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle like: ${e.toString()}'),
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
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// PRODUCT IMAGE SECTION
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  _currentProduct.imageURL,
                  height: 230,
                  width: double.infinity,
                  fit: BoxFit.fitHeight,
                ),
              ),
              const SizedBox(height: AppSpacing.xLarge),

              /// TITLE + FAVORITE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _currentProduct.name,
                      style: AppTextStyles.heading1,
                      maxLines: 2,
                    ),
                  ),
                  GestureDetector(
                    onTap: _isLoading ? null : _toggleLike,
                    child: _isLoading
                        ? const SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          )
                        : Icon(
                            _currentProduct.isLiked ?? false
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: AppColors.primary,
                            size: 30,
                          ),
                  ),
                ],
              ),
              Text(
                _currentProduct.tag.name.toUpperCase(),
                style: AppTextStyles.productCardCategory,
              ),
              const SizedBox(height: AppSpacing.xLarge),

              /// RATING STARS
              Builder(
                builder: (context) {
                  final rawRating = _currentProduct.averageRating ?? 0.0;
                  final rating = (rawRating.isNaN || rawRating.isInfinite)
                      ? 0.0
                      : rawRating.clamp(0.0, 5.0);
                  
                  return Row(
                    children: List.generate(
                      5,
                      (index) {
                        // Tam dolu yıldız kontrolü: rating >= index + 1
                        if (rating >= index + 1) {
                          return Icon(
                            Icons.star,
                            size: 30,
                            color: AppColors.primary,
                          );
                        } 
                        // Yarı dolu yıldız kontrolü: rating > index && rating < index + 1
                        else if (rating > index && rating < index + 1) {
                          return SizedBox(
                            width: 30,
                            height: 30,
                            child: Stack(
                              children: [
                                Icon(
                                  Icons.star_border,
                                  size: 30,
                                  color: AppColors.textSecondary,
                                ),
                                ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: rating - index,
                                    child: Icon(
                                      Icons.star,
                                      size: 30,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        } 
                        // Boş yıldız
                        else {
                          return Icon(
                            Icons.star_border,
                            size: 30,
                            color: AppColors.textSecondary,
                          );
                        }
                      },
                    ),
                  );
                },
              ),

              /// DESCRIPTION
              Text(
                _currentProduct.description ?? "",
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xLarge),

              /// REVIEWS TITLE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Reviews", style: AppTextStyles.heading2),
                  if (_reviews.isNotEmpty)
                    Text(
                      '${_reviews.length} review${_reviews.length > 1 ? 's' : ''}',
                      style: AppTextStyles.bodySecondary,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.medium),

              /// REVIEWS LIST
              if (_isLoadingReviews)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxLarge),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_errorMessage != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxLarge),
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
                    padding: const EdgeInsets.all(AppSpacing.xxLarge),
                    child: Text(
                      'No reviews yet. Be the first to review!',
                      style: AppTextStyles.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ..._reviews.map((review) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.large),
                      child: ReviewCard(
                        username: '@${review.ownerUserName}',
                        content: review.description ?? review.title,
                        rating: review.rating,
                        isSponsored: review.isCollaborative,
                        likeCount: review.likeCount,
                        isLiked: review.isLikedByCurrentUser,
                        onLikeTap: () async {
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

                            final newLikeStatus = await _interactionRepository.toggleReviewLike(
                              firebaseIdToken,
                              review.id,
                            );

                            // Review listesini güncelle
                            setState(() {
                              final index = _reviews.indexWhere((r) => r.id == review.id);
                              if (index != -1) {
                                // Review'ı güncelle - like durumunu değiştir
                                final updatedReview = ReviewDto(
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
                                  likeCount: newLikeStatus
                                      ? review.likeCount + 1
                                      : (review.likeCount > 0 ? review.likeCount - 1 : 0),
                                  isLikedByCurrentUser: newLikeStatus,
                                );
                                _reviews[index] = updatedReview;
                              }
                            });
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to toggle like: ${e.toString()}'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    )),

              const SizedBox(height: AppSpacing.xxLarge),
            ],
          ),
        ),
      ),

      /// ADD REVIEW BUTTON
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: AppButton(
          text: "Add a Review",
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddReviewPage(product: _currentProduct),
              ),
            );
            // Eğer review oluşturulduysa, review listesini yenile
            if (result == true) {
              _loadReviews();
            }
          },
          isLoading: false,
        ),
      ),
    );
  }
}
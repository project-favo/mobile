import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/review_card.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/custom_refresh_indicator.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/models/tag_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/repositories/product_repository.dart';
import 'add_review_page.dart';
import 'review_detail_page.dart';
import 'compare_product_select_page.dart';

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
  late ProductDto _currentProduct;
  bool _isLoadingProduct = false; // productId ile açıldıysa ürün yüklenene kadar
  List<ReviewDto> _reviews = [];
  bool _isLoadingReviews = true;
  String? _errorMessage;
  int _likeCount = 0;
  bool _hasLoadedLikeCount = false;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _currentProduct = widget.product!;
      _loadReviews();
      _refreshProductData();
      return;
    }
    // productId ile açıldı: placeholder ile hemen göster, arka planda ürünü yükle
    _currentProduct = _placeholderProduct(widget.productId!, widget.productName ?? '');
    _isLoadingProduct = true;
    _loadReviews();
    _loadProductById();
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
      final count = await _interactionRepository.getProductLikeCount(_currentProduct.id);
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

  /// Product'ı backend'den yeniden yükler (rating ve like durumu için)
  Future<void> _refreshProductData() async {
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      if (token == null) return;

      // Product'ı tamamen yeniden yükle
      final updatedProduct = await _productRepository.getProductById(
        _currentProduct.id,
        firebaseIdToken: token,
      );

      setState(() {
        _currentProduct = updatedProduct;
      });
      await _loadLikeCount();
    } catch (_) {}
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

      // Ensure session and get token
      final firebaseIdToken = await _sessionHelper.ensureSession();
      if (firebaseIdToken == null) {
        throw Exception('Failed to get Firebase ID token');
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
      _currentProduct = _currentProduct.copyWith(
        isLiked: !previousLikeStatus,
      );
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
        _currentProduct = _currentProduct.copyWith(
          isLiked: newLikeStatus,
        );
      });
      await _loadLikeCount();
    } catch (e) {
      // Hata durumunda optimistic update'i geri al
      setState(() {
        _currentProduct = _currentProduct.copyWith(
          isLiked: previousLikeStatus,
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
        iconTheme: const IconThemeData(color: AppColors.primary),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompareProductSelectPage(product1: _currentProduct),
                  ),
                );
              },
                child: const Text(
                'COMPARE',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: CustomRefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _loadReviews(),
            _refreshProductData(),
          ]);
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

              /// PRODUCT IMAGE SECTION with Hero animation
              Hero(
                tag: 'product_image_${_currentProduct.id}_${_currentProduct.imageURL}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    _currentProduct.imageURL,
                    height: 230,
                    width: double.infinity,
                    fit: BoxFit.fitHeight,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 230,
                        width: double.infinity,
                        color: AppColors.textSecondary.withOpacity(0.1),
                        child: const Icon(
                          Icons.image_not_supported,
                          color: AppColors.textSecondary,
                          size: 48,
                        ),
                      );
                    },
                  ),
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
                    onTap: _toggleLike,
                    child: Icon(
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

              /// RATING STARS with rating and review count
              Builder(
                builder: (context) {
                  final rawRating = _currentProduct.averageRating ?? 0.0;
                  final rating = (rawRating.isNaN || rawRating.isInfinite)
                      ? 0.0
                      : rawRating.clamp(0.0, 5.0);
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Stars
                          ...List.generate(
                            5,
                            (index) {
                              // Tam dolu yıldız kontrolü: rating >= index + 1
                              if (rating >= index + 1) {
                                return const Icon(
                                  Icons.star,
                                  size: 24,
                                  color: AppColors.primary,
                                );
                              } 
                              // Yarı dolu yıldız kontrolü: rating > index && rating < index + 1
                              else if (rating > index && rating < index + 1) {
                                return SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Stack(
                                    children: [
                                      const Icon(
                                        Icons.star_border,
                                        size: 24,
                                        color: AppColors.textSecondary,
                                      ),
                                      ClipRect(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: rating - index,
                                          child: const Icon(
                                            Icons.star,
                                            size: 24,
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
                                return const Icon(
                                  Icons.star_border,
                                  size: 24,
                                  color: AppColors.textSecondary,
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          // Rating text
                          Text(
                            rating.toStringAsFixed(1),
                            style: AppTextStyles.bodyBold.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Review count + like count
                      Row(
                        children: [
                          Icon(
                            Icons.reviews_outlined,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_reviews.length} review${_reviews.length != 1 ? 's' : ''}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(
                            Icons.favorite,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          if (_hasLoadedLikeCount) ...[
                            const SizedBox(width: 4),
                            Text(
                              '$_likeCount likes',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
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
                ...List.generate(
                  3,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.large),
                    child: ReviewCardSkeleton(),
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
                                  content: Text('Please login to upvote reviews'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                            return;
                          }

                          // Optimistic update - UI'ı hemen güncelle
                          final reviewIndex = _reviews.indexWhere((r) => r.id == review.id);
                          if (reviewIndex != -1) {
                            final previousLikeStatus = _reviews[reviewIndex].isLikedByCurrentUser;
                            final previousLikeCount = _reviews[reviewIndex].likeCount;
                            
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
                                likeCount: previousLikeStatus 
                                    ? (previousLikeCount > 0 ? previousLikeCount - 1 : 0)
                                    : previousLikeCount + 1,
                                isLikedByCurrentUser: !previousLikeStatus,
                              );
                            });
                          }

                          try {
                            // Token al (session zaten var)
                            final token = await _sessionHelper.getTokenAndSetHeader();
                            if (token == null) {
                              throw Exception('Failed to get Firebase ID token');
                            }

                            // Upvote toggle yap
                            final newLikeStatus = await _interactionRepository.toggleReviewLike(
                              token,
                              review.id,
                            );

                            // Review'ı backend'den yeniden çek (güncel like durumu için)
                            try {
                              final updatedReview = await _reviewRepository.getReviewById(
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
                                    isCollaborative: currentReview.isCollaborative,
                                    rating: currentReview.rating,
                                    createdAt: currentReview.createdAt,
                                    productId: currentReview.productId,
                                    productName: currentReview.productName,
                                    ownerId: currentReview.ownerId,
                                    ownerUserName: currentReview.ownerUserName,
                                    mediaList: currentReview.mediaList,
                                    likeCount: newLikeStatus
                                        ? (currentReview.likeCount + 1)
                                        : (currentReview.likeCount > 0 ? currentReview.likeCount - 1 : 0),
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
                              final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
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
                    )),

              const SizedBox(height: AppSpacing.xxLarge),
            ],
          ),
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
              SlideUpRoute(
                page: AddReviewPage(product: _currentProduct),
              ),
            );
            // Eğer review oluşturulduysa, review listesini ve product verilerini (rating dahil) yenile
            if (result == true) {
              await Future.wait([
                _loadReviews(),
                _refreshProductData(),
              ]);
            }
          },
          isLoading: false,
        ),
      ),
    );
  }
}
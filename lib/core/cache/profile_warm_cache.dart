import '../../features/auth/data/models/product_dto.dart';
import '../../features/auth/data/models/review_dto.dart';
import '../../features/auth/data/models/user_response_dto.dart';

class ProfileWarmSnapshot {
  final UserResponseDto user;
  final List<ReviewDto> myReviews;
  /// Sunucu toplam yorum sayısı (sayfalı /api/reviews/me); null → eski önbellek.
  final int? myReviewsServerTotal;
  final List<ProductDto> wishlist;
  final Map<String, ProductDto> reviewProductHints;
  final int followerCount;
  final int followingCount;
  /// GET /api/reviews/me/average-rating (sayfa değişiminde titremesin)
  final double? myReviewsGlobalAverage;

  const ProfileWarmSnapshot({
    required this.user,
    required this.myReviews,
    this.myReviewsServerTotal,
    required this.wishlist,
    this.reviewProductHints = const {},
    this.followerCount = 0,
    this.followingCount = 0,
    this.myReviewsGlobalAverage,
  });
}

/// Warm cache for Profile tab transitions.
class ProfileWarmCache {
  ProfileWarmCache._();
  static final ProfileWarmCache instance = ProfileWarmCache._();

  ProfileWarmSnapshot? _snapshot;

  ProfileWarmSnapshot? peek() => _snapshot;

  void remember({
    required UserResponseDto user,
    required List<ReviewDto> myReviews,
    int? myReviewsServerTotal,
    required List<ProductDto> wishlist,
    Map<String, ProductDto> reviewProductHints = const {},
    int followerCount = 0,
    int followingCount = 0,
    double? myReviewsGlobalAverage,
  }) {
    _snapshot = ProfileWarmSnapshot(
      user: user,
      myReviews: List<ReviewDto>.from(myReviews),
      myReviewsServerTotal: myReviewsServerTotal,
      wishlist: List<ProductDto>.from(wishlist),
      reviewProductHints: Map<String, ProductDto>.from(reviewProductHints),
      followerCount: followerCount,
      followingCount: followingCount,
      myReviewsGlobalAverage: myReviewsGlobalAverage,
    );
  }

  void clear() {
    _snapshot = null;
  }
}


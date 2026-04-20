import '../../features/auth/data/models/product_dto.dart';
import '../../features/auth/data/models/review_dto.dart';
import '../../features/auth/data/models/user_response_dto.dart';

class ProfileWarmSnapshot {
  final UserResponseDto user;
  final List<ReviewDto> myReviews;
  final List<ProductDto> wishlist;

  const ProfileWarmSnapshot({
    required this.user,
    required this.myReviews,
    required this.wishlist,
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
    required List<ProductDto> wishlist,
  }) {
    _snapshot = ProfileWarmSnapshot(
      user: user,
      myReviews: List<ReviewDto>.from(myReviews),
      wishlist: List<ProductDto>.from(wishlist),
    );
  }
}


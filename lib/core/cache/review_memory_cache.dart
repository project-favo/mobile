import '../../features/auth/data/models/review_dto.dart';

/// In-memory review cache for faster product detail transitions.
class ReviewMemoryCache {
  ReviewMemoryCache._();
  static final ReviewMemoryCache instance = ReviewMemoryCache._();

  static const int _maxEntries = 80;
  final Map<String, List<ReviewDto>> _map = {};

  List<ReviewDto>? peek(String productId) {
    final id = productId.trim();
    if (id.isEmpty) return null;
    final cached = _map[id];
    if (cached == null) return null;
    return List<ReviewDto>.from(cached);
  }

  void remember(String productId, List<ReviewDto> reviews) {
    final id = productId.trim();
    if (id.isEmpty) return;
    _map[id] = List<ReviewDto>.from(reviews);
    while (_map.length > _maxEntries) {
      _map.remove(_map.keys.first);
    }
  }

  void remove(String productId) {
    _map.remove(productId.trim());
  }

  /// Ürün listesinden tek review kaldır (silindikten sonra).
  void removeReviewFromProduct(String productId, String reviewId) {
    final pid = productId.trim();
    final rid = reviewId.trim();
    if (pid.isEmpty || rid.isEmpty) return;
    final list = _map[pid];
    if (list == null) return;
    _map[pid] = list.where((r) => r.id != rid).toList();
  }
}


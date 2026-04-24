import '../../features/auth/data/models/product_dto.dart';
import '../../features/auth/data/models/review_dto.dart';
import '../../features/auth/data/models/tag_dto.dart';

/// Warm cache for SearchPage bootstrap data.
class SearchWarmCache {
  SearchWarmCache._();
  static final SearchWarmCache instance = SearchWarmCache._();

  List<TagDto> _rootTags = const [];
  List<ProductDto> _seedProducts = const [];
  List<TopReviewerDto> _topReviewers = const [];
  DateTime? _topReviewersFetchedAt;

  void rememberRootTags(List<TagDto> tags) {
    _rootTags = List<TagDto>.from(tags);
  }

  void rememberSeedProducts(List<ProductDto> products) {
    _seedProducts = List<ProductDto>.from(products);
  }

  void rememberTopReviewers(List<TopReviewerDto> reviewers) {
    _topReviewers = List<TopReviewerDto>.from(reviewers);
    _topReviewersFetchedAt = DateTime.now();
  }

  List<TagDto> peekRootTags() => List<TagDto>.from(_rootTags);
  List<ProductDto> peekSeedProducts() => List<ProductDto>.from(_seedProducts);
  List<TopReviewerDto> peekTopReviewers() => List<TopReviewerDto>.from(_topReviewers);
  DateTime? peekTopReviewersFetchedAt() => _topReviewersFetchedAt;

  void clear() {
    _rootTags = const [];
    _seedProducts = const [];
    _topReviewers = const [];
    _topReviewersFetchedAt = null;
  }
}


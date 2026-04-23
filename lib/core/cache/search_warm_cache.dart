import '../../features/auth/data/models/product_dto.dart';
import '../../features/auth/data/models/tag_dto.dart';

/// Warm cache for SearchPage bootstrap data.
class SearchWarmCache {
  SearchWarmCache._();
  static final SearchWarmCache instance = SearchWarmCache._();

  List<TagDto> _rootTags = const [];
  List<ProductDto> _seedProducts = const [];

  void rememberRootTags(List<TagDto> tags) {
    _rootTags = List<TagDto>.from(tags);
  }

  void rememberSeedProducts(List<ProductDto> products) {
    _seedProducts = List<ProductDto>.from(products);
  }

  List<TagDto> peekRootTags() => List<TagDto>.from(_rootTags);
  List<ProductDto> peekSeedProducts() => List<ProductDto>.from(_seedProducts);

  void clear() {
    _rootTags = const [];
    _seedProducts = const [];
  }
}


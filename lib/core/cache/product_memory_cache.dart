import '../../features/auth/data/models/product_dto.dart';

/// Son kullanılan ürünler (profil → ReviewPage gibi geçişlerde anında gösterim).
class ProductMemoryCache {
  ProductMemoryCache._();
  static final ProductMemoryCache instance = ProductMemoryCache._();

  static const int _maxEntries = 80;
  final Map<String, ProductDto> _map = {};

  ProductDto? peek(String productId) {
    final id = productId.trim();
    if (id.isEmpty) return null;
    return _map[id];
  }

  void remember(ProductDto product) {
    final id = product.id.trim();
    if (id.isEmpty) return;
    _map[id] = product;
    while (_map.length > _maxEntries) {
      _map.remove(_map.keys.first);
    }
  }

  void remove(String productId) {
    _map.remove(productId.trim());
  }

  void clear() {
    _map.clear();
  }
}

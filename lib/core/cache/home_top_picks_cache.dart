import '../../features/auth/data/models/product_dto.dart';

/// Haftalık beğeni / sana özel banner ürünleri (çıkışta [clear] ile temizlenir).
enum HomeTopPicksTab { weeklyLikes, forYou }

class HomeTopPicksCache {
  static final Map<HomeTopPicksTab, List<ProductDto>> _static = {};

  static List<ProductDto>? peek(HomeTopPicksTab tab) {
    final p = _static[tab];
    if (p == null || p.isEmpty) return null;
    return List<ProductDto>.from(p);
  }

  static void remember(HomeTopPicksTab tab, List<ProductDto> products) {
    _static[tab] = List<ProductDto>.from(products);
  }

  static void clear() {
    _static.clear();
  }
}

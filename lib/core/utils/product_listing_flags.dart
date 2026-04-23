bool _truthyFlag(dynamic v) {
  if (v == true) return true;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'suspended') {
      return true;
    }
  }
  if (v is num && v == 1) return true;
  return false;
}

bool _falsyFlag(dynamic v) {
  if (v == false) return true;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'false' || s == '0' || s == 'no') return true;
  }
  return false;
}

/// [ReviewDto] ve [ProductDto] JSON'unda ürünün vitrinden kalkmış / askıda olduğunu tespit eder.
bool isProductDataNotListedInMap(Map<String, dynamic> m) {
  if (_truthyFlag(m['suspended']) ||
      _truthyFlag(m['productSuspended']) ||
      _truthyFlag(m['isSuspended']) ||
      _truthyFlag(m['is_suspended']) ||
      _truthyFlag(m['product_suspended']) ||
      _truthyFlag(m['isDelisted']) ||
      _truthyFlag(m['is_delisted']) ||
      _truthyFlag(m['isBanned']) ||
      _truthyFlag(m['banned']) ||
      _truthyFlag(m['isRemoved']) ||
      _truthyFlag(m['removed'])) {
    return true;
  }
  if (m['active'] is bool && (m['active'] as bool) == false) {
    return true;
  }
  // Spring / Jackson: `boolean isActive()` → JSON’da çoğu zaman `active`, bazen `isActive`.
  if (m['isActive'] is bool && (m['isActive'] as bool) == false) {
    return true;
  }
  if (m['is_active'] is bool && (m['is_active'] as bool) == false) {
    return true;
  }
  // Bazı API'ler 0/1 veya 0.0 sayı taşır
  for (final k in ['active', 'isActive', 'is_active', 'productActive', 'product_active']) {
    if (m[k] is num && (m[k] as num) == 0) {
      return true;
    }
  }
  if (m['productActive'] is bool && (m['productActive'] as bool) == false) {
    return true;
  }
  if (_falsyFlag(m['isActive']) ||
      _falsyFlag(m['is_active']) ||
      _falsyFlag(m['active']) ||
      _falsyFlag(m['productActive']) ||
      _falsyFlag(m['enabled']) ||
      _falsyFlag(m['isEnabled']) ||
      _falsyFlag(m['is_enabled'])) {
    return true;
  }
  if (m['visible'] is bool && (m['visible'] as bool) == false) {
    return true;
  }
  if (_falsyFlag(m['visible']) || _falsyFlag(m['isVisible']) || _falsyFlag(m['is_visible'])) {
    return true;
  }
  if (_falsyFlag(m['listed']) ||
      _falsyFlag(m['isListed']) ||
      _falsyFlag(m['is_listed']) ||
      _falsyFlag(m['published']) ||
      _falsyFlag(m['isPublished']) ||
      _falsyFlag(m['is_published']) ||
      _falsyFlag(m['isPublic']) ||
      _falsyFlag(m['is_public']) ||
      _falsyFlag(m['public']) ||
      _falsyFlag(m['inCatalog']) ||
      _falsyFlag(m['in_catalog'])) {
    return true;
  }
  if (_truthyFlag(m['deactivated']) || _truthyFlag(m['unavailable'])) {
    return true;
  }
  final st = (m['status'] ?? m['productStatus'] ?? m['state'] ?? m['listingStatus'] ?? m['productState'] ?? '')
      .toString()
      .toLowerCase();
  if (st.contains('suspend') ||
      st.contains('unpublish') ||
      st == 'hidden' ||
      st == 'inactive' ||
      st == 'disabled' ||
      st == 'banned' ||
      st == 'delisted' ||
      st == 'unavailable' ||
      st == 'removed' ||
      st == 'rejected' ||
      st == 'suspended' ||
      st == 'dismissed') {
    return true;
  }
  // Ana sayfa / katalog: vitrin dışı
  if (_falsyFlag(m['inHomeFeed']) ||
      _falsyFlag(m['in_home_feed']) ||
      _falsyFlag(m['onHomePage']) ||
      _falsyFlag(m['on_home_page']) ||
      _falsyFlag(m['onHome']) ||
      _falsyFlag(m['showOnHomePage']) ||
      _falsyFlag(m['show_on_home_page']) ||
      _falsyFlag(m['showInHome']) ||
      _falsyFlag(m['show_in_home']) ||
      _falsyFlag(m['showInStore']) ||
      _falsyFlag(m['inPublicFeed']) ||
      _falsyFlag(m['in_public_feed']) ||
      _falsyFlag(m['inPublicCatalog']) ||
      _falsyFlag(m['inSearch']) ||
      _falsyFlag(m['in_search']) ||
      _falsyFlag(m['searchable']) ||
      _falsyFlag(m['discoverable']) ||
      _falsyFlag(m['browsable']) ||
      _falsyFlag(m['catalogVisible']) ||
      _falsyFlag(m['visibleInStore'])) {
    return true;
  }
  if (_truthyFlag(m['excludedFromHome']) ||
      _truthyFlag(m['excludedFromFeed']) ||
      _truthyFlag(m['hiddenFromHome']) ||
      _truthyFlag(m['suspendedFromFeed'])) {
    return true;
  }
  return false;
}

void _forNestedProductMaps(
  Map<String, dynamic> json,
  void Function(Map<String, dynamic> m) each,
) {
  const keys = [
    'product',
    'productDto',
    'productData',
    'productDetails',
    'productInfo',
  ];
  for (final k in keys) {
    final v = json[k];
    if (v is Map<String, dynamic>) {
      each(v);
    }
  }
}

/// Tüm veya sadece nested `product` alanından türet.
bool isProductNotListedFromJsonMap(Map<String, dynamic> json) {
  if (isProductDataNotListedInMap(json)) return true;
  var any = false;
  _forNestedProductMaps(json, (m) {
    if (isProductDataNotListedInMap(m)) any = true;
  });
  return any;
}

/// GET /api/products cevabında [imageURL] kasıtlı boş; backend `suspended` vb. alanları taşımıyorsa
/// profil "My reviews" satırında yine de askı varyantı gösterilsin.
bool isNotListedImpliedByEmptyProductImage(String? imageUrl) {
  return imageUrl == null || imageUrl.toString().trim().isEmpty;
}

/// [root] ve iç içe (max [maxDepth]) tüm [Map] düğümlerinde askı sinyali aranır
/// (Spring `data`, `result`, `product` sarmalında kalan alanlar için).
bool isProductNotListedInResponseJson(
  Map<String, dynamic> root, {
  int maxDepth = 5,
  int depth = 0,
}) {
  if (depth > maxDepth) return false;
  if (isProductDataNotListedInMap(root)) return true;
  for (final v in root.values) {
    if (v is Map<String, dynamic>) {
      if (isProductNotListedInResponseJson(v, maxDepth: maxDepth, depth: depth + 1)) {
        return true;
      }
    }
  }
  return false;
}

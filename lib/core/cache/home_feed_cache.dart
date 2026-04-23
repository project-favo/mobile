import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/models/product_search_result_dto.dart';

/// Ana sayfa "Tümü" sekmesinin ilk sayfası: bellek + disk. Okuma önce buradan, sonra API.
class HomeFeedCache {
  HomeFeedCache._();
  static final HomeFeedCache instance = HomeFeedCache._();

  static const _prefsKey = 'favo_home_feed_page0_v1';

  ProductSearchResultDto? _memory;

  /// Bellek (splash disk restore veya son başarılı [setFromResult]).
  ProductSearchResultDto? peek() {
    if (_memory == null || _memory!.content.isEmpty) return null;
    return ProductSearchResultDto(
      content: List.from(_memory!.content),
      totalElements: _memory!.totalElements,
      totalPages: _memory!.totalPages,
      size: _memory!.size,
      number: _memory!.number,
    );
  }

  void setFromResult(ProductSearchResultDto r) {
    if (r.content.isEmpty) return;
    _memory = ProductSearchResultDto(
      content: List.from(r.content),
      totalElements: r.totalElements,
      totalPages: r.totalPages,
      size: r.size,
      number: r.number,
    );
    // ignore: discarded_futures
    _saveDisk();
  }

  /// Uygulama açılışında splash’tan [await] edilir — Home açılmadan bellek dolar.
  Future<void> restoreFromDisk() async {
    if (_memory != null && _memory!.content.isNotEmpty) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _memory = ProductSearchResultDto.fromJson(map);
    } catch (_) {
      await p.remove(_prefsKey);
    }
  }

  Future<void> _saveDisk() async {
    if (_memory == null) return;
    final p = await SharedPreferences.getInstance();
    try {
      await p.setString(_prefsKey, jsonEncode(_memory!.toJson()));
    } catch (_) {}
  }

  void clear() {
    _memory = null;
    // ignore: discarded_futures
    _removeDisk();
  }

  Future<void> _removeDisk() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsKey);
  }
}

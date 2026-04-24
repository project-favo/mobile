/// Arka plan [Timer.periodic] aralıklarının tek kaynağı: pil, ağ ve tutarlı UX.
///
/// Aynı tür ekran aynı segmenti kullanır; değer değişikliği tek yerden yapılır.
abstract final class AppBackgroundTimers {
  AppBackgroundTimers._();

  // --- Okunmamış & mesaj ---

  /// Global tab bar: okunmamış sohbet sayısı. Çok kısa aralık gereksiz [ensureSession] yükü üretir.
  static const Duration messageUnreadPoll = Duration(seconds: 12);

  /// Açık sohbet: yeni mesaj / durum. ~3 sn yerine 4 sn: denge.
  static const Duration chatThreadPoll = Duration(seconds: 4);

  // --- Listeler & feed ---

  /// Friend feed, activity, profil yoklama, takip listesi, konuşma listesi, bildirim listesi, ürün vitrin tespiti.
  static const Duration standardListPoll = Duration(seconds: 5);

  /// Ana katalog: yeni ürün taraması.
  static const Duration homeFeedBackgroundPoll = Duration(seconds: 10);

  // --- Oturum ---

  /// [SessionHelper] uzak hesap durumu (deaktif) denetimi.
  static const Duration accountStatusCheck = Duration(seconds: 60);

  // --- Sadece UI (ağ yok) ---

  /// Ana sayfa üst bant / hero otomatik sayfa.
  static const Duration homeHeroCarousel = Duration(seconds: 5);

  /// Banner / tanıtım carousel adımı (küçük widget içi).
  static const Duration homePromoBannerStep = Duration(seconds: 4);
}

/// Ana sayfada kategori seçili değilken kullanılan ürün kaynağı.
enum HomeFeedMode {
  /// Mevcut `GET /api/products/home`.
  discover,

  /// Son 7 İstanbul günü aktif yorum sayısına göre.
  trendingReviews,

  /// Bu hafta (Pzt–Pzt) LIKE sayısına göre.
  weeklyLikes,

  /// Giriş gerekli: `GET /api/products/feed/personalized`.
  personalized,
}

extension HomeFeedModeLabels on HomeFeedMode {
  String get chipLabel => switch (this) {
        HomeFeedMode.discover => 'Discover',
        HomeFeedMode.trendingReviews => 'Trending',
        HomeFeedMode.weeklyLikes => 'This week',
        HomeFeedMode.personalized => 'For you',
      };

  String get topStripTitle => switch (this) {
        HomeFeedMode.discover => 'Top 10 Products',
        HomeFeedMode.trendingReviews => 'Trending (7-day reviews)',
        HomeFeedMode.weeklyLikes => 'Popular this week',
        HomeFeedMode.personalized => 'Recommended for you',
      };
}

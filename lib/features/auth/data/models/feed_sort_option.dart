enum FeedSortOption {
  newest,
  ratingDesc,
  reviewsDesc;

  String get apiValue => switch (this) {
        FeedSortOption.newest => 'newest',
        FeedSortOption.ratingDesc => 'rating_desc',
        FeedSortOption.reviewsDesc => 'reviews_desc',
      };

  String get label => switch (this) {
        FeedSortOption.newest => 'Newest',
        FeedSortOption.ratingDesc => 'Top Rated',
        FeedSortOption.reviewsDesc => 'Most Reviewed',
      };

  static FeedSortOption fromApiValue(String? value) {
    if (value == null || value.isEmpty) return FeedSortOption.newest;
    // Removed sorts (low / least): treat persisted or legacy API as default feed
    if (value == 'rating_asc' || value == 'reviews_asc') {
      return FeedSortOption.newest;
    }
    return FeedSortOption.values.firstWhere(
      (option) => option.apiValue == value,
      orElse: () => FeedSortOption.newest,
    );
  }
}

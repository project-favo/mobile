enum FeedSortOption {
  newest,
  ratingDesc,
  ratingAsc,
  reviewsDesc,
  reviewsAsc;

  String get apiValue => switch (this) {
        FeedSortOption.newest => 'newest',
        FeedSortOption.ratingDesc => 'rating_desc',
        FeedSortOption.ratingAsc => 'rating_asc',
        FeedSortOption.reviewsDesc => 'reviews_desc',
        FeedSortOption.reviewsAsc => 'reviews_asc',
      };

  String get label => switch (this) {
        FeedSortOption.newest => 'Newest',
        FeedSortOption.ratingDesc => 'Top Rated',
        FeedSortOption.ratingAsc => 'Low Rated',
        FeedSortOption.reviewsDesc => 'Most Reviewed',
        FeedSortOption.reviewsAsc => 'Least Reviewed',
      };

  static FeedSortOption fromApiValue(String? value) {
    return FeedSortOption.values.firstWhere(
      (option) => option.apiValue == value,
      orElse: () => FeedSortOption.newest,
    );
  }
}

import '../../features/activity/domain/activity_models.dart';

class FriendFeedWarmSnapshot {
  final List<ActivityItem> items;
  final int page;
  final int totalPages;

  const FriendFeedWarmSnapshot({
    required this.items,
    required this.page,
    required this.totalPages,
  });
}

class FriendFeedMemoryCache {
  FriendFeedMemoryCache._();
  static final FriendFeedMemoryCache instance = FriendFeedMemoryCache._();

  FriendFeedWarmSnapshot? _snapshot;

  FriendFeedWarmSnapshot? peek() => _snapshot;

  void remember({
    required List<ActivityItem> items,
    required int page,
    required int totalPages,
  }) {
    _snapshot = FriendFeedWarmSnapshot(
      items: List<ActivityItem>.from(items),
      page: page,
      totalPages: totalPages,
    );
  }

  void clear() {
    _snapshot = null;
  }
}

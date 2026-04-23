import '../../features/activity/domain/activity_models.dart';

class ActivityWarmSnapshot {
  final List<ActivityItem> items;
  final int page;
  final int totalPages;
  final int totalElements;
  /// Takip listesi senkronu tamamlanmadan kısa süreli "Follow" flash’ı önler.
  final Set<String> followingUserIds;

  const ActivityWarmSnapshot({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalElements,
    this.followingUserIds = const {},
  });
}

class ActivityMemoryCache {
  ActivityMemoryCache._();
  static final ActivityMemoryCache instance = ActivityMemoryCache._();

  ActivityWarmSnapshot? _snapshot;

  ActivityWarmSnapshot? peek() => _snapshot;

  void remember({
    required List<ActivityItem> items,
    required int page,
    required int totalPages,
    required int totalElements,
    Set<String>? followingUserIds,
  }) {
    _snapshot = ActivityWarmSnapshot(
      items: List<ActivityItem>.from(items),
      page: page,
      totalPages: totalPages,
      totalElements: totalElements,
      followingUserIds: followingUserIds == null
          ? const {}
          : Set<String>.from(followingUserIds),
    );
  }

  void clear() {
    _snapshot = null;
  }
}


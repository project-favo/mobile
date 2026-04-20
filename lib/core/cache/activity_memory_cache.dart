import '../../features/activity/domain/activity_models.dart';

class ActivityWarmSnapshot {
  final List<ActivityItem> items;
  final int page;
  final int totalPages;
  final int totalElements;

  const ActivityWarmSnapshot({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalElements,
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
  }) {
    _snapshot = ActivityWarmSnapshot(
      items: List<ActivityItem>.from(items),
      page: page,
      totalPages: totalPages,
      totalElements: totalElements,
    );
  }
}


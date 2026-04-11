import 'activity_type.dart';

class ActivityUser {
  const ActivityUser({
    required this.id,
    required this.username,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String? avatarUrl;
}

/// Target for like / comment / review (product or content summary).
class ActivityTargetContent {
  const ActivityTargetContent({
    required this.title,
    this.thumbnailUrl,
    this.productId,
    this.reviewId,
  });

  final String title;
  final String? thumbnailUrl;
  final String? productId;
  final String? reviewId;
}

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.type,
    required this.user,
    this.targetContent,
    required this.timestamp,
    this.isRead = false,
    required this.lineText,
  });

  final String id;
  final ActivityType type;
  final ActivityUser user;
  final ActivityTargetContent? targetContent;
  final DateTime timestamp;
  final bool isRead;

  /// Notification [body] or [title] — shown as returned by the API.
  final String lineText;

  ActivityItem copyWith({
    bool? isRead,
    String? lineText,
  }) {
    return ActivityItem(
      id: id,
      type: type,
      user: user,
      targetContent: targetContent,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      lineText: lineText ?? this.lineText,
    );
  }
}

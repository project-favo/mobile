import 'package:favo_mobile/core/utils/entity_active.dart';

import '../domain/activity_models.dart';
import '../domain/activity_type.dart';
import 'friends_feed_dto.dart';

ActivityType activityTypeFromFriendsFeed(String rawType) {
  final t = rawType.toUpperCase();
  if (t == 'PRODUCT_LIKE' || t.contains('LIKE')) return ActivityType.like;
  if (t == 'REVIEW' || t.contains('REVIEW')) return ActivityType.review;
  return ActivityType.review;
}

/// Deaktif / askı / vitrin dışı satırları listeden çıkarır (üst seviyede ayrıca [getUserById] ile de süzülür).
List<ActivityItem> activityItemsFromFriendsFeedDtos(
  Iterable<FriendsFeedItemDto> content,
) {
  return content
      .where(isFriendsFeedItemForUi)
      .map(activityItemFromFriendsFeed)
      .toList();
}

ActivityItem activityItemFromFriendsFeed(FriendsFeedItemDto e) {
  final type = activityTypeFromFriendsFeed(e.type);
  final username =
      e.actorUserName.trim().isNotEmpty ? e.actorUserName.trim() : 'User';
  final displayName = (e.actorDisplayName ?? '').trim();
  final actorName = displayName.isNotEmpty ? displayName : username;

  final productTitle = (e.productName ?? '').trim();
  final reviewTitle = (e.reviewTitle ?? '').trim();
  final targetTitle = productTitle.isNotEmpty
      ? productTitle
      : (reviewTitle.isNotEmpty ? reviewTitle : 'Product');

  final lineText = type == ActivityType.like
      ? '$actorName liked this product'
      : '$actorName reviewed this product';

  return ActivityItem(
    id: e.id.isNotEmpty
        ? e.id
        : '${e.type}_${e.actorUserId}_${e.productId ?? ''}_${e.createdAt?.millisecondsSinceEpoch ?? 0}',
    type: type,
    user: ActivityUser(
      id: e.actorUserId,
      username: username,
      avatarUrl: e.actorProfilePhotoUrl,
    ),
    targetContent: ActivityTargetContent(
      title: targetTitle,
      thumbnailUrl: e.productImageUrl,
      productId: (e.productId ?? '').trim().isEmpty ? null : e.productId,
      reviewId: (e.reviewId ?? '').trim().isEmpty ? null : e.reviewId,
    ),
    timestamp: e.createdAt ?? DateTime.now(),
    isRead: true,
    lineText: lineText,
    isActorInactive: e.isActorAccountDeactivated || e.isActorUserInactive,
  );
}

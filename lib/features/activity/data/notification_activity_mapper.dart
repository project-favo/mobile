import 'dart:convert';

import '../../auth/data/models/notification_dto.dart';
import '../domain/activity_models.dart';
import '../domain/activity_type.dart';

Map<String, dynamic>? _parsePayload(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return null;
}

ActivityType activityTypeFromNotification(String rawType) {
  final t = rawType.toUpperCase();
  if (t.contains('FOLLOW')) return ActivityType.follow;
  if (t.contains('LIKE')) return ActivityType.like;
  if (t.contains('COMMENT')) return ActivityType.comment;
  if (t.contains('REVIEW')) return ActivityType.review;
  return ActivityType.review;
}

/// Maps a notification API row to an [ActivityItem].
ActivityItem activityItemFromNotification(NotificationDto n) {
  final p = _parsePayload(n.payloadJson);
  final type = activityTypeFromNotification(n.type);

  final displayNameFromApi = (n.actorDisplayName != null &&
          n.actorDisplayName!.trim().isNotEmpty)
      ? n.actorDisplayName!.trim()
      : 'User';

  final actor = n.actor;
  final actorUserName = actor?.userName?.trim();
  final actorName = (actorUserName != null && actorUserName.isNotEmpty)
      ? actorUserName
      : displayNameFromApi;

  final followerId = p?['followerUserId']?.toString() ?? '';
  final actorUserId = p?['actorUserId']?.toString() ?? '';

  final actorIdStr =
      actor != null && actor.id > 0 ? actor.id.toString() : '';

  final userIdForFollow = type == ActivityType.follow
      ? (actorIdStr.isNotEmpty ? actorIdStr : followerId)
      : (actorIdStr.isNotEmpty
          ? actorIdStr
          : (actorUserId.isNotEmpty ? actorUserId : followerId));

  final avatarFromActor = actor?.profileImageUrl.trim();
  final avatarFallback = p?['actorAvatarUrl']?.toString().trim();
  final rawAvatar = (avatarFromActor != null && avatarFromActor.isNotEmpty)
      ? avatarFromActor
      : avatarFallback;
  final resolvedAvatar =
      rawAvatar != null && rawAvatar.isNotEmpty ? rawAvatar : null;

  final user = ActivityUser(
    id: userIdForFollow,
    username: actorName,
    avatarUrl: resolvedAvatar,
  );

  final productId = p?['productId']?.toString() ??
      (n.product?.id != 0 ? n.product?.id.toString() : null);
  final productName = p?['productName']?.toString() ?? n.product?.name;
  final payloadImage = p?['productImageUrl']?.toString();
  final productImageUrl =
      (payloadImage != null && payloadImage.trim().isNotEmpty)
          ? payloadImage
          : n.product?.imageURL;
  final reviewId = p?['reviewId']?.toString();

  ActivityTargetContent? target;
  if ((productId != null && productId.isNotEmpty) ||
      (productImageUrl != null && productImageUrl.isNotEmpty)) {
    target = ActivityTargetContent(
      title: (productName != null && productName.isNotEmpty)
          ? productName
          : n.title,
      thumbnailUrl: productImageUrl,
      productId:
          (productId != null && productId.isNotEmpty) ? productId : null,
      reviewId: (reviewId != null && reviewId.isNotEmpty) ? reviewId : null,
    );
  }

  final title = target?.title ?? 'this product';
  late final String lineText;
  switch (type) {
    case ActivityType.follow:
      lineText = '$actorName started following you.';
      break;
    case ActivityType.like:
      if (target?.reviewId != null && target!.reviewId!.isNotEmpty) {
        lineText = '$actorName liked your review.';
      } else {
        lineText = '$actorName liked a product related to you: $title';
      }
      break;
    case ActivityType.review:
      lineText = '$actorName reviewed a product related to you: $title';
      break;
    case ActivityType.comment:
      lineText = '$actorName commented on a product related to you: $title';
      break;
  }

  return ActivityItem(
    id: n.id,
    type: type,
    user: user,
    targetContent: target,
    timestamp: n.createdAt ?? DateTime.now(),
    isRead: !n.isUnread,
    lineText: lineText,
    isActorInactive: n.actor != null && n.actor!.isAccountInactive,
  );
}

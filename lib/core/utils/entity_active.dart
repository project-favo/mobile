import 'package:favo_mobile/features/activity/data/friends_feed_dto.dart';
import 'package:favo_mobile/features/auth/data/models/conversation_dto.dart';
import 'package:favo_mobile/features/auth/data/models/notification_dto.dart';
import 'package:favo_mobile/features/auth/data/models/product_dto.dart';
import 'package:favo_mobile/features/auth/data/models/review_dto.dart';

// Ürün ve yorum için tekrarlanan "gösterilebilir mi?" mantığının tek giriş noktası.

/// Ürün vitrinde ve detayda gösterilebilir (sunucu askı/pasif bayrakları yok).
bool isProductEntityActive(ProductDto product) => !product.isProductNotListed;

/// Yorum listede ve detayda gösterilebilir (ürün veya yorum tarafı pasif değil).
bool isReviewEntityVisible(ReviewDto review) =>
    !review.isProductNotListed && !review.isReviewInactive;

/// [isProductEntityActive] ile aynı; negatif isim API/JSON düşünce tarzı için.
bool isProductInactive(ProductDto product) => product.isProductNotListed;

/// [isReviewEntityVisible] tersi.
bool isReviewInactiveOrHidden(ReviewDto review) => !isReviewEntityVisible(review);

/// Listelerde kullan: API hâlâ satır döndürse bile UI filtreler.
List<ReviewDto> filterVisibleReviews(Iterable<ReviewDto> reviews) =>
    reviews.where(isReviewEntityVisible).toList();

/// Bildirim: pasif / vitrin dışı actor; askıdaki ürün özeti. Actor yoksa (sistem) geçer.
bool isNotificationListEntryVisible(NotificationDto n) {
  final a = n.actor;
  if (a != null && a.id > 0 && a.isAccountInactive) return false;
  final p = n.product;
  if (p == null) return true;
  return !p.isProductNotListed;
}

List<NotificationDto> filterVisibleNotifications(
  Iterable<NotificationDto> list,
) =>
    list.where(isNotificationListEntryVisible).toList();

/// Arkadaş akışı: deaktif/askı actor veya vitrin dışı ürüne atıf.
bool isFriendsFeedItemForUi(FriendsFeedItemDto e) {
  if (e.isActorAccountDeactivated) return false;
  if (e.isActorUserInactive) return false;
  final pid = e.productId?.trim() ?? '';
  if (pid.isEmpty) return true;
  return !e.isProductSnapshotNotListed;
}

List<FriendsFeedItemDto> filterVisibleFriendsFeedItems(
  Iterable<FriendsFeedItemDto> items,
) =>
    items.where(isFriendsFeedItemForUi).toList();

bool isConversationUserVisible(ConversationUserDto u) => !u.isAccountInactive;

bool isConversationDtoVisible(ConversationDto c) =>
    isConversationUserVisible(c.otherParticipant);

List<ConversationDto> filterVisibleConversations(
  Iterable<ConversationDto> list,
) =>
    list.where(isConversationDtoVisible).toList();

List<ConversationUserDto> filterVisibleConversationUsers(
  Iterable<ConversationUserDto> list,
) =>
    list.where(isConversationUserVisible).toList();

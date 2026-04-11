import 'package:flutter/material.dart';

import 'notification_dto.dart';

/// Backend `type` alanına göre bildirimleri profesyonel gruplara ayırır.
enum NotificationSection {
  followers,
  likes,
  productReviews,
  other;

  String get title => switch (this) {
        NotificationSection.followers => 'Followers',
        NotificationSection.likes => 'Likes & reactions',
        NotificationSection.productReviews => 'Products & reviews',
        NotificationSection.other => 'Other',
      };

  IconData get icon => switch (this) {
        NotificationSection.followers => Icons.person_add_alt_1_outlined,
        NotificationSection.likes => Icons.favorite_outline_rounded,
        NotificationSection.productReviews => Icons.rate_review_outlined,
        NotificationSection.other => Icons.notifications_outlined,
      };

  /// Sabit grup sırası (öncelik: sosyal → etkileşim → ürün).
  int get sortIndex => switch (this) {
        NotificationSection.followers => 0,
        NotificationSection.likes => 1,
        NotificationSection.productReviews => 2,
        NotificationSection.other => 3,
      };
}

NotificationSection notificationSectionForType(String type) {
  final t = type.toUpperCase();
  if (t.contains('FOLLOW')) {
    return NotificationSection.followers;
  }
  if (t.contains('LIKE')) {
    return NotificationSection.likes;
  }
  if (t.contains('REVIEW') ||
      t.contains('PRODUCT') ||
      t.contains('SHARED') ||
      t.contains('COMMENT')) {
    return NotificationSection.productReviews;
  }
  return NotificationSection.other;
}

/// Gruplara göre sıralı bildirim listeleri (her grup içi: en yeni üstte).
Map<NotificationSection, List<NotificationDto>> groupNotifications(
  List<NotificationDto> items,
) {
  final map = <NotificationSection, List<NotificationDto>>{
    for (final s in NotificationSection.values) s: [],
  };
  for (final n in items) {
    map[notificationSectionForType(n.type)]!.add(n);
  }
  for (final list in map.values) {
    list.sort((a, b) {
      final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
  }
  return map;
}

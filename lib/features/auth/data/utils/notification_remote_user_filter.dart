import 'dart:collection';

import 'package:favo_mobile/core/utils/entity_active.dart';
import 'package:favo_mobile/core/utils/exceptions.dart';
import 'package:favo_mobile/features/activity/data/friends_feed_dto.dart';
import 'package:favo_mobile/features/auth/data/models/notification_dto.dart';
import 'package:favo_mobile/features/auth/data/services/auth_service.dart';

class _CacheEntry {
  _CacheEntry(this.listable, this.expires);
  final bool listable;
  final DateTime expires;
}

/// [getUserById] / 404 önbelleği. [getUserById] dolu ve profil engelli değilse listable; yalnızca
/// `u == null` iken profil resmi 404 ile doğrulanır.
final class RemoteNotificationUserListabilityCache {
  RemoteNotificationUserListabilityCache._();
  static final RemoteNotificationUserListabilityCache instance =
      RemoteNotificationUserListabilityCache._();

  static const Duration _ttlListable = Duration(seconds: 45);
  static const Duration _ttlUnlisted = Duration(seconds: 60);
  static const Duration _ttlUnknown = Duration(seconds: 25);

  final Map<int, _CacheEntry> _byUserId = HashMap();

  void clear() => _byUserId.clear();

  void invalidateUser(int id) => _byUserId.remove(id);

  /// [getUserById] sonrası bu satırlar tekrar değerlendirilsin (tek yenileme).
  void invalidateForNotificationDtos(Iterable<NotificationDto> list) {
    for (final n in list) {
      final id = n.resolvedUserIdForVisibilityCheck;
      if (id != null && id > 0) invalidateUser(id);
    }
  }

  /// `true` = satır kalsın. [getUserById] yeterliyse resim istenmez; yalnızca `u == null` iken 404 kontrolü.
  Future<bool> isUserListableForNotificationRow(
    AuthService auth,
    int id,
  ) async {
    if (id <= 0) return true;
    final now = DateTime.now();
    final e = _byUserId[id];
    if (e != null && e.expires.isAfter(now)) {
      return e.listable;
    }
    try {
      final u = await auth.getUserById(id.toString());
      if (u != null && u.isProfileViewBlocked) {
        _byUserId[id] = _CacheEntry(false, now.add(_ttlUnlisted));
        return false;
      }
      if (u != null) {
        _byUserId[id] = _CacheEntry(true, now.add(_ttlListable));
        return true;
      }
      final imgOnly = await auth.fetchUserProfileImage(id.toString());
      if (imgOnly != null && imgOnly.isNotFound) {
        _byUserId[id] = _CacheEntry(false, now.add(_ttlUnlisted));
        return false;
      }
      _byUserId[id] = _CacheEntry(true, now.add(_ttlUnknown));
      return true;
    } on TargetUserNotAvailableException {
      _byUserId[id] = _CacheEntry(false, now.add(_ttlUnlisted));
      return false;
    } catch (_) {
      return true;
    }
  }
}

/// Önce JSON/ürün filtresi, sonra deaktif/silinen kullanıcı = profilde açılamaz kuralı.
Future<List<NotificationDto>> filterNotificationsHidingUnlistedUsers(
  Iterable<NotificationDto> list,
  AuthService auth, {
  RemoteNotificationUserListabilityCache? cache,
}) async {
  final c = cache ?? RemoteNotificationUserListabilityCache.instance;
  final pre = list.where(isNotificationListEntryVisibleForRemoteList).toList();
  final ids = <int>{};
  for (final n in pre) {
    final id = n.resolvedUserIdForVisibilityCheck;
    if (id != null && id > 0) ids.add(id);
  }
  if (ids.isEmpty) return pre;

  final bad = <int>{};
  await Future.wait(ids.map((id) async {
    if (!await c.isUserListableForNotificationRow(auth, id)) {
      bad.add(id);
    }
  }));
  if (bad.isEmpty) return pre;
  return pre.where((n) {
    final id = n.resolvedUserIdForVisibilityCheck;
    if (id == null || id <= 0) return true;
    return !bad.contains(id);
  }).toList();
}

/// Arkadaş akışı: satırdaki [actorUserId] için aynı [getUserById] kuralı.
Future<List<FriendsFeedItemDto>> filterFriendsFeedHidingUnlistedActors(
  Iterable<FriendsFeedItemDto> items,
  AuthService auth, {
  RemoteNotificationUserListabilityCache? cache,
}) async {
  final c = cache ?? RemoteNotificationUserListabilityCache.instance;
  final pre = filterVisibleFriendsFeedItems(items);
  final ids = <int>{};
  for (final e in pre) {
    final id = int.tryParse(e.actorUserId.trim());
    if (id != null && id > 0) ids.add(id);
  }
  if (ids.isEmpty) return pre;

  final bad = <int>{};
  await Future.wait(ids.map((id) async {
    if (!await c.isUserListableForNotificationRow(auth, id)) {
      bad.add(id);
    }
  }));
  if (bad.isEmpty) return pre;
  return pre.where((e) {
    final id = int.tryParse(e.actorUserId.trim());
    if (id == null || id <= 0) return true;
    return !bad.contains(id);
  }).toList();
}

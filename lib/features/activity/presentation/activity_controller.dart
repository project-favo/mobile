import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/config/list_paging.dart';
import '../../../core/cache/activity_memory_cache.dart';
import '../../../core/cache/following_id_set_cache.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/in_flight_id_lock.dart';
import '../../../core/utils/load_profile_image_bytes.dart';
import '../../../core/utils/session_helper.dart';
import '../../auth/data/models/notification_dto.dart';
import '../../auth/data/repositories/interaction_repository.dart';
import '../../auth/data/repositories/notification_repository.dart';
import '../../auth/data/services/auth_service.dart';
import '../../auth/data/utils/notification_remote_user_filter.dart';
import '../data/notification_activity_mapper.dart';
import '../domain/activity_models.dart';

/// Activity feed via notification endpoints (`GET/PATCH /api/notifications/...`).
class ActivityController extends ChangeNotifier {
  ActivityController({
    NotificationRepository? notificationRepository,
    InteractionRepository? interactionRepository,
    SessionHelper? sessionHelper,
  })  : _notifications = notificationRepository ?? NotificationRepository(),
        _interactions = interactionRepository ?? InteractionRepository(),
        _sessionHelper = sessionHelper ?? SessionHelper();

  final NotificationRepository _notifications;
  final InteractionRepository _interactions;
  final SessionHelper _sessionHelper;
  final AuthService _auth = AuthService();
  final InFlightIdLock _followToggleLock = InFlightIdLock();

  List<ActivityItem> _items = [];
  final Set<String> _followingUserIds = {};
  int _page = 0;
  int _totalPages = 1;
  int _totalElements = 0;
  bool _loadingFirst = true;
  bool _loadingMore = false;
  String? _errorMessage;

  List<ActivityItem> get items => List.unmodifiable(_items);
  /// Sunucudaki toplam bildirim sayısı (sayfalama üst bilgisi).
  int get totalNotificationCount => _totalElements;
  bool get loadingFirst => _loadingFirst;
  bool get loadingMore => _loadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _page + 1 < _totalPages;
  bool isFollowingUser(String userId) =>
      userId.isNotEmpty && _followingUserIds.contains(userId);

  /// Aynı actor + type + target kombinasyonundan sadece en yeni birini tutar.
  List<ActivityItem> _deduplicateItems(List<ActivityItem> items) {
    final seen = <String>{};
    final result = <ActivityItem>[];
    for (final item in items) {
      final key =
          '${item.user.id}|${item.type.name}|${item.targetContent?.reviewId ?? ''}|${item.targetContent?.productId ?? ''}';
      if (item.user.id.isEmpty || seen.add(key)) {
        result.add(item);
      }
    }
    return result;
  }

  bool hydrateFromCache() {
    final warm = ActivityMemoryCache.instance.peek();
    if (warm == null || warm.items.isEmpty) return false;
    _items = List<ActivityItem>.from(warm.items);
    _page = warm.page;
    _totalPages = warm.totalPages;
    _totalElements = warm.totalElements;
    _followingUserIds
      ..clear()
      ..addAll(warm.followingUserIds);
    _mergeFollowFromGlobalCache();
    _loadingFirst = false;
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  void _mergeFollowFromGlobalCache() {
    if (!FollowingIdSetCache.instance.isReady) return;
    for (final item in _items) {
      final id = item.user.id;
      if (id.isEmpty) continue;
      if (FollowingIdSetCache.instance.contains(id)) {
        _followingUserIds.add(id);
      } else {
        _followingUserIds.remove(id);
      }
    }
  }

  void _prefetchAvatarsForItems(Iterable<ActivityItem> items) {
    for (final e in items) {
      final u = e.user.avatarUrl;
      if (u != null && u.trim().isNotEmpty) {
        unawaited(loadProfileImageBytesFromRaw(u));
      }
      final thumb = e.targetContent?.thumbnailUrl;
      if (thumb != null && thumb.trim().isNotEmpty) {
        _warmImageCache(thumb);
      }
    }
  }

  void _warmImageCache(String url) {
    final provider = NetworkImage(url);
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, __) => stream.removeListener(listener),
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  Future<void> loadFirstPage({bool flushRemoteListabilityCaches = false}) async {
    // Cache'den içerik zaten gösteriliyorsa skeleton açma (stale-while-revalidate)
    final silentRefresh = _items.isNotEmpty;
    if (!silentRefresh) {
      _loadingFirst = true;
      notifyListeners();
    }
    _errorMessage = null;
    _page = 0;
    try {
      if (flushRemoteListabilityCaches) {
        RemoteNotificationUserListabilityCache.instance.clear();
        RemoteNotificationProductListabilityCache.instance.clear();
        RemoteNotificationReviewContextCache.instance.clear();
      }
      final page = await _notifications.getNotifications(
        page: 0,
        size: kStandardListPageSize,
      );
      final visible = await filterNotificationsHidingUnlistedUsers(
        page.content,
        _auth,
      );
      _items = _deduplicateItems(
        visible.map(activityItemFromNotification).toList(),
      );
      _page = page.number;
      _totalPages = page.totalPages;
      _totalElements = page.totalElements;
      _prefetchAvatarsForItems(_items);
      await _syncFollowStatesForCurrentItems(refetchFollowingSet: true);
    } catch (e) {
      _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
    } finally {
      _loadingFirst = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _loadingFirst || !hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final next = await _notifications.getNotifications(
        page: _page + 1,
        size: kStandardListPageSize,
      );
      final visible = await filterNotificationsHidingUnlistedUsers(
        next.content,
        _auth,
      );
      final appended =
          visible.map(activityItemFromNotification).toList();
      _items = _deduplicateItems([..._items, ...appended]);
      _page = next.number;
      _totalPages = next.totalPages;
      _prefetchAvatarsForItems(appended);
      await _syncFollowStatesForCurrentItems(refetchFollowingSet: true);
    } catch (_) {
      // Ignore; user can pull to refresh or scroll again
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  void _writeActivitySnapshot() {
    if (_items.isEmpty) return;
    ActivityMemoryCache.instance.remember(
      items: _items,
      page: _page,
      totalPages: _totalPages,
      totalElements: _totalElements,
      followingUserIds: _followingUserIds,
    );
  }

  /// [refetchFollowingSet]: liste API’den yeni geldiyede takip seti eski kaldığında Follow/Following hatası olmasın.
  Future<void> _syncFollowStatesForCurrentItems({
    bool refetchFollowingSet = false,
  }) async {
    final token = await _sessionHelper.ensureSession();
    if (token == null) {
      _writeActivitySnapshot();
      return;
    }

    final ids = _items
        .where((e) => e.user.id.isNotEmpty)
        .map((e) => e.user.id)
        .toSet()
        .toList();

    if (ids.isEmpty) {
      _writeActivitySnapshot();
      return;
    }

    try {
      await FollowingIdSetCache.instance.ensureLoaded(
        _interactions,
        _auth,
        _sessionHelper,
        force: refetchFollowingSet,
      );
      final myFollowing = FollowingIdSetCache.instance.snapshot;
      for (final id in ids) {
        if (myFollowing.contains(id)) {
          _followingUserIds.add(id);
        } else {
          _followingUserIds.remove(id);
        }
      }
    } catch (_) {
      await _syncFollowStatesPerIdIsFollowing(token, ids);
    } finally {
      _writeActivitySnapshot();
    }
  }

  /// Yedek: takip seti yüklenemezse satır başına `is-following` (N paralel).
  Future<void> _syncFollowStatesPerIdIsFollowing(
    String token,
    List<String> ids,
  ) async {
    await Future.wait(
      ids.map((id) async {
        try {
          final f = await _interactions.isFollowing(token, id);
          if (f) {
            _followingUserIds.add(id);
          } else {
            _followingUserIds.remove(id);
          }
        } catch (_) {}
      }),
    );
  }

  Future<void> toggleFollow(String userId) async {
    if (userId.isEmpty) return;
    if (!_followToggleLock.tryEnter(userId)) return;
    final token = await _sessionHelper.ensureSession();
    if (token == null) {
      _followToggleLock.leave(userId);
      return;
    }
    try {
      final following = await _interactions.toggleFollow(token, userId);
      if (following) {
        _followingUserIds.add(userId);
      } else {
        _followingUserIds.remove(userId);
      }
      FollowingIdSetCache.instance.applyToggle(userId, following);
      _writeActivitySnapshot();
      notifyListeners();
    } catch (_) {
      rethrow;
    } finally {
      _followToggleLock.leave(userId);
    }
  }

  /// Activity ekranı görüntülendiğinde: sunucuda tümünü okundu işaretle + yerel satırlar.
  Future<void> markEntireFeedViewed() async {
    try {
      await _notifications.markAllRead();
      _items = _items.map((e) => e.copyWith(isRead: true)).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0 || _items[i].isRead) return;
    try {
      await _notifications.markRead(id);
      _items = [
        ..._items.sublist(0, i),
        _items[i].copyWith(isRead: true),
        ..._items.sublist(i + 1),
      ];
      notifyListeners();
    } catch (_) {
      rethrow;
    }
  }

  Future<void> prependFromPush(NotificationDto n) async {
    final visible = await filterNotificationsHidingUnlistedUsers([n], _auth);
    if (visible.isEmpty) return;
    final m = visible.first;
    final mapped = activityItemFromNotification(m);
    if (_items.any((e) => e.id == mapped.id)) return;

    // Same actor + type + target already exists: move to top (dedup like/unlike spam)
    if (mapped.user.id.isNotEmpty) {
      final dupeIndex = _items.indexWhere(
        (e) =>
            e.type == mapped.type &&
            e.user.id == mapped.user.id &&
            e.targetContent?.reviewId == mapped.targetContent?.reviewId &&
            e.targetContent?.productId == mapped.targetContent?.productId,
      );
      if (dupeIndex != -1) {
        _items = [
          mapped,
          ..._items.sublist(0, dupeIndex),
          ..._items.sublist(dupeIndex + 1),
        ];
        _prefetchAvatarsForItems([mapped]);
        notifyListeners();
        unawaited(_syncFollowStatesForCurrentItems(refetchFollowingSet: true));
        return;
      }
    }

    _items = [mapped, ..._items];
    if (_totalElements > 0) _totalElements += 1;
    _prefetchAvatarsForItems([mapped]);
    notifyListeners();
    unawaited(_syncFollowStatesForCurrentItems(refetchFollowingSet: true));
  }
}

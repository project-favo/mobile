import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/cache/activity_memory_cache.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/load_profile_image_bytes.dart';
import '../../../core/utils/session_helper.dart';
import '../../auth/data/models/notification_dto.dart';
import '../../auth/data/repositories/interaction_repository.dart';
import '../../auth/data/repositories/notification_repository.dart';
import '../data/notification_activity_mapper.dart';
import '../domain/activity_models.dart';
import '../domain/activity_type.dart';

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
    _loadingFirst = false;
    _errorMessage = null;
    notifyListeners();
    return true;
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

  Future<void> loadFirstPage() async {
    // Cache'den içerik zaten gösteriliyorsa skeleton açma (stale-while-revalidate)
    final silentRefresh = _items.isNotEmpty;
    if (!silentRefresh) {
      _loadingFirst = true;
      notifyListeners();
    }
    _errorMessage = null;
    _page = 0;
    try {
      final page = await _notifications.getNotifications(page: 0, size: 20);
      _items = _deduplicateItems(
        page.content.map(activityItemFromNotification).toList(),
      );
      _page = page.number;
      _totalPages = page.totalPages;
      _totalElements = page.totalElements;
      ActivityMemoryCache.instance.remember(
        items: _items,
        page: _page,
        totalPages: _totalPages,
        totalElements: _totalElements,
      );
      _prefetchAvatarsForItems(_items);
      await _syncFollowStatesForCurrentItems();
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
      final next =
          await _notifications.getNotifications(page: _page + 1, size: 20);
      final appended = next.content.map(activityItemFromNotification).toList();
      _items = _deduplicateItems([..._items, ...appended]);
      _page = next.number;
      _totalPages = next.totalPages;
      ActivityMemoryCache.instance.remember(
        items: _items,
        page: _page,
        totalPages: _totalPages,
        totalElements: _totalElements,
      );
      _prefetchAvatarsForItems(appended);
      await _syncFollowStatesForCurrentItems();
    } catch (_) {
      // Ignore; user can pull to refresh or scroll again
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _syncFollowStatesForCurrentItems() async {
    final token = await _sessionHelper.ensureSession();
    if (token == null) return;

    final ids = _items
        .where((e) => e.type == ActivityType.follow && e.user.id.isNotEmpty)
        .map((e) => e.user.id)
        .toSet()
        .toList();

    if (ids.isEmpty) return;

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
    final token = await _sessionHelper.ensureSession();
    if (token == null) return;
    try {
      final following = await _interactions.toggleFollow(token, userId);
      if (following) {
        _followingUserIds.add(userId);
      } else {
        _followingUserIds.remove(userId);
      }
      notifyListeners();
    } catch (_) {
      rethrow;
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

  void prependFromPush(NotificationDto n) {
    final mapped = activityItemFromNotification(n);
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
        unawaited(_syncFollowStatesForCurrentItems());
        return;
      }
    }

    _items = [mapped, ..._items];
    if (_totalElements > 0) _totalElements += 1;
    _prefetchAvatarsForItems([mapped]);
    notifyListeners();
    unawaited(_syncFollowStatesForCurrentItems());
  }
}

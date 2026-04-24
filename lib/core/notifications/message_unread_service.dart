import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/auth/data/repositories/message_repository.dart';
import '../config/app_background_timers.dart';
import '../utils/app_logger.dart';
import '../utils/session_helper.dart';

/// Singleton that tracks total unread-conversation count across the app.
///
/// Works like [NotificationRealtimeService]: callers call [attach]/[detach]
/// and the service maintains a background polling loop while any widget is
/// attached.  [unreadCount] is a [ValueNotifier] so widgets can react with
/// [ValueListenableBuilder] without ever calling [setState].
class MessageUnreadService {
  MessageUnreadService._();
  static final MessageUnreadService instance = MessageUnreadService._();

  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  int _refs = 0;
  Timer? _pollTimer;
  bool _refreshing = false;

  void attach() {
    _refs++;
    if (_refs == 1) {
      _startPolling();
    }
  }

  void detach() {
    if (_refs > 0) _refs--;
    if (_refs == 0) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _refresh();
    _pollTimer = Timer.periodic(
      AppBackgroundTimers.messageUnreadPoll,
      (_) => _refresh(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Force an immediate refresh (e.g., right after opening the messages tab).
  Future<void> refreshNow() => _refresh();

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final token = await SessionHelper().ensureSession();
      if (token == null) {
        unreadCount.value = 0;
        return;
      }
      final page = await MessageRepository().getConversations(
        page: 0,
        size: 50,
      );
      final count = page.content.where((c) => c.unreadCount > 0).length;
      unreadCount.value = count;
    } catch (e, st) {
      AppLogger.warnSilencedError('MessageUnreadService._refresh', e, st);
    } finally {
      _refreshing = false;
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../config/api_config.dart';
import '../utils/session_helper.dart';
import '../../features/auth/data/models/notification_dto.dart';
import '../../features/auth/data/repositories/notification_repository.dart';

/// STOMP: `/user/queue/notifications` (CONNECT header: Bearer token).
class NotificationRealtimeService {
  NotificationRealtimeService._();
  static final NotificationRealtimeService instance =
      NotificationRealtimeService._();

  final ValueNotifier<int> unreadCount = ValueNotifier(0);
  final StreamController<NotificationPushEvent> _pushController =
      StreamController<NotificationPushEvent>.broadcast();

  Stream<NotificationPushEvent> get pushStream => _pushController.stream;

  int _refs = 0;
  StompClient? _stompClient;
  bool _connecting = false;

  void attach() {
    _refs++;
    if (_refs == 1) {
      unawaited(_connect());
    }
  }

  void detach() {
    if (_refs > 0) _refs--;
    if (_refs == 0) {
      _disconnect();
    }
  }

  Future<void> refreshUnread() async {
    try {
      final token = await SessionHelper().ensureSession();
      if (token == null) {
        unreadCount.value = 0;
        return;
      }
      final n = await NotificationRepository().getUnreadCount();
      unreadCount.value = n;
      if (_refs > 0 && _stompClient == null && !_connecting) {
        unawaited(_connect());
      }
    } catch (_) {
      if (_refs == 0) {
        unreadCount.value = 0;
      }
    }
  }

  Future<void> _connect() async {
    if (_connecting || _stompClient != null) return;
    _connecting = true;
    try {
      final token = await SessionHelper().ensureSession();
      if (token == null) {
        _connecting = false;
        return;
      }

      String wsBase = ApiConfig.baseUrl;
      if (wsBase.startsWith('https://')) {
        wsBase = wsBase.replaceFirst('https://', 'wss://');
      } else if (wsBase.startsWith('http://')) {
        wsBase = wsBase.replaceFirst('http://', 'ws://');
      }

      _stompClient = StompClient(
        config: StompConfig(
          url: '$wsBase${ApiConfig.wsNativePath}',
          stompConnectHeaders: {'Authorization': 'Bearer $token'},
          webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
          onConnect: _onStompConnected,
          onWebSocketError: (dynamic _) {},
          onStompError: (StompFrame _) {},
        ),
      );

      _stompClient?.activate();
    } finally {
      _connecting = false;
    }
  }

  void _onStompConnected(StompFrame frame) {
    _stompClient?.subscribe(
      destination: '/user/queue/notifications',
      callback: (StompFrame frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        try {
          final Map<String, dynamic> data =
              jsonDecode(body) as Map<String, dynamic>;
          final u = (data['unreadCount'] as num?)?.toInt() ?? 0;
          unreadCount.value = u;

          NotificationDto? incoming;
          final rawN = data['notification'];
          if (rawN is Map<String, dynamic>) {
            incoming = NotificationDto.fromJson(rawN);
          }
          _pushController.add(NotificationPushEvent(
            unreadCount: u,
            notification: incoming,
          ));
        } catch (_) {}
      },
    );
  }

  void _disconnect() {
    _stompClient?.deactivate();
    _stompClient = null;
  }
}

class NotificationPushEvent {
  final int unreadCount;
  final NotificationDto? notification;

  NotificationPushEvent({
    required this.unreadCount,
    this.notification,
  });
}

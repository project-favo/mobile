import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'app_badge_sync.dart';

/// Ayrı isolate + terminated; [main] içinde [Firebase.initializeApp] öncesine kayıt gerekir.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) {
    debugPrint('FCM background: ${message.data}');
  }
  await applyPushBadgeFromMessageData(message.data);
}

import 'dart:async';

import 'package:favo_mobile/app.dart';
import 'package:favo_mobile/core/network/api_client.dart';
import 'package:favo_mobile/core/network/firebase_auth_api_interceptor.dart';
import 'package:favo_mobile/core/notifications/fcm_background_handler.dart';
import 'package:favo_mobile/core/notifications/push_notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase'i başlat
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  
  // API Client'i initialize et
  ApiClient().initialize();
  attachFirebaseIdTokenToAllRequests();

  // Onboarding daha once tamamlandiysa tekrar gosterme
  final prefs = await SharedPreferences.getInstance();
  final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

  runApp(
    MyApp(
      onboardingCompleted: onboardingCompleted,
    ),
  );
  if (!kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PushNotificationService.instance.install());
    });
  }
}


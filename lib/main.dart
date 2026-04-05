import 'package:favo_mobile/app.dart';
import 'package:favo_mobile/core/network/api_client.dart';
import 'package:favo_mobile/core/network/firebase_auth_api_interceptor.dart';
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
}


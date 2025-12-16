import 'package:favo_mobile/app.dart';
import 'package:favo_mobile/core/network/api_client.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase'i başlat
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // API Client'i initialize et
  ApiClient().initialize();
  
  runApp(const MyApp());
}


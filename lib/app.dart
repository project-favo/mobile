import 'package:flutter/material.dart';
import 'routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_splash_gate.dart';

class MyApp extends StatelessWidget {
  final bool onboardingCompleted;

  const MyApp({
    super.key,
    required this.onboardingCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Favo',
      theme: AppTheme.lightTheme,
      routes: AppRoutes.routes,
      home: AuthSplashGate(onboardingCompleted: onboardingCompleted),
    );
  }
}

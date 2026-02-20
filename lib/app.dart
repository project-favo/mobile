import 'package:flutter/material.dart';
import 'routes/app_routes.dart';
import 'core/theme/app_theme.dart';

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({
    super.key,
    required this.initialRoute,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Favo',
      theme: AppTheme.lightTheme,
      initialRoute: initialRoute,
      routes: AppRoutes.routes,
    );
  }
}

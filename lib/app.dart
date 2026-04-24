import 'package:flutter/material.dart';
import 'core/navigation/app_route_observer.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_splash_gate.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

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
      scrollBehavior: const AppScrollBehavior(),
      navigatorKey: appNavigatorKey,
      navigatorObservers: [appRouteObserver],
      scaffoldMessengerKey: appScaffoldMessengerKey,
      routes: AppRoutes.routes,
      home: AuthSplashGate(onboardingCompleted: onboardingCompleted),
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: content,
        );
      },
    );
  }
}

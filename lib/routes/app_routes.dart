import 'package:flutter/material.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/auth/presentation/home_page.dart';
import '../features/auth/presentation/onboarding_page.dart';

class AppRoutes {
  static const onboarding = '/';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';

  static final Map<String, WidgetBuilder> routes = {
    onboarding: (_) => const OnboardingPage(),
    login: (_) => const LoginPage(),
    register: (_) => const RegisterPage(),
    home: (_) => const HomePage(),
  };
}

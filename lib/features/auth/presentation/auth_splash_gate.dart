import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'onboarding_page.dart';

/// Açılışta: oturum yok → onboarding/login; oturum var → ana sayfa.
/// E-posta doğrulaması zorunlu değil; profil ekranından Firebase link ile tamamlanır.
class AuthSplashGate extends StatefulWidget {
  final bool onboardingCompleted;

  const AuthSplashGate({super.key, required this.onboardingCompleted});

  @override
  State<AuthSplashGate> createState() => _AuthSplashGateState();
}

class _AuthSplashGateState extends State<AuthSplashGate> {
  Widget? _screen;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!widget.onboardingCompleted) {
      if (!mounted) return;
      setState(() => _screen = const OnboardingPage());
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _screen = const LoginPage());
      return;
    }

    try {
      await user.reload();
    } catch (_) {}

    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser == null) {
      setState(() => _screen = const LoginPage());
      return;
    }

    setState(() => _screen = const HomePage());
  }

  @override
  Widget build(BuildContext context) {
    if (_screen == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    return _screen!;
  }
}

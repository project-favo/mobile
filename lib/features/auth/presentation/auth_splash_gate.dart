import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/cache/conversation_list_cache.dart';
import '../../../core/cache/home_feed_cache.dart';
import '../../../core/cache/search_warm_cache.dart';
import '../../../core/utils/session_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/services/auth_service.dart';
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
  final TagRepository _tagRepository = TagRepository();
  final ProductRepository _productRepository = ProductRepository();
  final SessionHelper _sessionHelper = SessionHelper();

  Future<void> _warmHomeCache() async {
    try {
      final token = await _sessionHelper.ensureSession();
      try {
        final tags = await _tagRepository.getRootTags(token);
        SearchWarmCache.instance.rememberRootTags(tags);
      } catch (_) {}
      try {
        final feed = await _productRepository.getHomeFeed(
          page: 0,
          size: 10,
          firebaseIdToken: token,
        );
        SearchWarmCache.instance.rememberSeedProducts(feed.content);
        HomeFeedCache.instance.setFromResult(feed);
      } catch (_) {}
    } catch (_) {}
  }

  /// Oturum kullanıcısını (getMe) splash sırasında yükler; yorum ekranlarında sahiplik gecikmesini azaltır.
  Future<void> _warmCurrentUser() async {
    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) return;
      await AuthService().getMe();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final minSplashFuture = Future.delayed(const Duration(milliseconds: 800));

    if (!widget.onboardingCompleted) {
      await minSplashFuture;
      if (!mounted) return;
      setState(() => _screen = const OnboardingPage());
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await minSplashFuture;
      if (!mounted) return;
      setState(() => _screen = const LoginPage());
      return;
    }

    try {
      await user.reload();
    } catch (_) {}

    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser == null) {
      await minSplashFuture;
      setState(() => _screen = const LoginPage());
      return;
    }

    await HomeFeedCache.instance.restoreFromDisk();
    await ConversationListCache.instance.restoreFromDisk();

    await Future.wait([
      minSplashFuture,
      _warmHomeCache().timeout(const Duration(seconds: 3), onTimeout: () {}),
      _warmCurrentUser().timeout(const Duration(seconds: 4), onTimeout: () {}),
    ]);
    if (!mounted) return;
    setState(() => _screen = const HomePage());
  }

  @override
  Widget build(BuildContext context) {
    if (_screen == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: _FavoLaunchSplash(),
      );
    }
    return _screen!;
  }
}

class _FavoLaunchSplash extends StatelessWidget {
  const _FavoLaunchSplash();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.96, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            builder: (context, value, child) =>
                Transform.scale(scale: value, child: child),
            child: SizedBox(
              width: 160,
              child: Image.asset(
                'assets/images/homepage_logo2.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Loading FAVO...',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

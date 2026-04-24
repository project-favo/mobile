import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/cache/conversation_list_cache.dart';
import '../../../core/cache/home_feed_cache.dart';
import '../../../core/cache/search_warm_cache.dart';
import '../../../core/utils/session_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
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

class _FavoLaunchSplash extends StatefulWidget {
  const _FavoLaunchSplash();

  @override
  State<_FavoLaunchSplash> createState() => _FavoLaunchSplashState();
}

class _FavoLaunchSplashState extends State<_FavoLaunchSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<double> _taglineOpacity;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _opacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );
    _scale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.72, curve: Curves.easeOutCubic),
      ),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.background,
            Color.lerp(AppColors.background, Colors.white, 0.45)!,
            AppColors.background,
          ],
          stops: const [0.0, 0.48, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.18,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.08),
                        AppColors.primary.withValues(alpha: 0.02),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _opacity,
                    child: ScaleTransition(
                      scale: _scale,
                      child: SizedBox(
                        width: 168,
                        height: 168,
                        child: Image.asset(
                          'assets/images/homepage_logo2.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.shopping_bag_rounded,
                            size: 96,
                            color: AppColors.primary.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: Text(
                      'Discover. Review. Share.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                  SizedBox(height: 24 + bottomInset),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

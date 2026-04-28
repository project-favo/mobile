import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      await user.reload().timeout(const Duration(seconds: 12));
    } catch (_) {}

    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser == null) {
      await minSplashFuture;
      setState(() => _screen = const LoginPage());
      return;
    }

    try {
      await HomeFeedCache.instance
          .restoreFromDisk()
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
    try {
      await ConversationListCache.instance
          .restoreFromDisk()
          .timeout(const Duration(seconds: 6));
    } catch (_) {}

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
      return Scaffold(
        backgroundColor: const Color(0xFFFAFAFB),
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: const Color(0xFFFAFAFB),
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: const _FavoLaunchSplash(),
        ),
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
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _loaderOpacity;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    _opacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.52, curve: Curves.easeOutCubic),
    );
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.68, curve: Curves.easeOutCubic),
      ),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.38, 1.0, curve: Curves.easeOutCubic),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.38, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _loaderOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
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
    final w = MediaQuery.sizeOf(context).width;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFAFAFB),
            Color(0xFFF4F5F7),
            Color(0xFFECEEF1),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -w * 0.15,
            right: -w * 0.2,
            child: IgnorePointer(
              child: Container(
                width: w * 0.75,
                height: w * 0.75,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.045),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -w * 0.25,
            left: -w * 0.15,
            child: IgnorePointer(
              child: Container(
                width: w * 0.65,
                height: w * 0.65,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.03),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                FadeTransition(
                  opacity: _opacity,
                  child: ScaleTransition(
                    scale: _scale,
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            blurRadius: 40,
                            offset: const Offset(0, 18),
                            spreadRadius: -12,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 120,
                        height: 120,
                        child: Image.asset(
                          'assets/images/homepage_logo2.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.shopping_bag_rounded,
                            size: 72,
                            color: AppColors.primary.withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SlideTransition(
                  position: _taglineSlide,
                  child: FadeTransition(
                    opacity: _taglineOpacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Discover · Review · Share',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.textPrimary.withValues(alpha: 0.82),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: 40,
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: _loaderOpacity,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 20 + bottomInset),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.primary.withValues(alpha: 0.75),
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

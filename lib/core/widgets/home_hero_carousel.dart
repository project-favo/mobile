import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_background_timers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Ana sayfa üst banner: otomatik kaydırmalı carousel.
class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({super.key});

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroSlide {
  final String title;
  final String subtitle;
  final List<Color> gradient;

  const _HomeHeroSlide({
    required this.title,
    required this.subtitle,
    required this.gradient,
  });
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  static const _slides = <_HomeHeroSlide>[
    _HomeHeroSlide(
      title: 'Discover picks',
      subtitle: 'Curated products for you',
      gradient: [Color(0xFF910029), Color(0xFFB91C4C)],
    ),
    _HomeHeroSlide(
      title: 'Trending now',
      subtitle: 'What the community loves this week',
      gradient: [Color(0xFF6B0A3A), Color(0xFF910029)],
    ),
    _HomeHeroSlide(
      title: 'Share your take',
      subtitle: 'Reviews help everyone choose better',
      gradient: [Color(0xFF4A0D28), Color(0xFF7D1440)],
    ),
  ];

  late final PageController _pageController;
  Timer? _autoTimer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 1);
    _autoTimer = Timer.periodic(AppBackgroundTimers.homeHeroCarousel, (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_page + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 148,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, index) {
                final s = _slides[index];
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: s.gradient,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xLarge,
                      AppSpacing.large,
                      AppSpacing.xLarge,
                      AppSpacing.medium,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s.title,
                          style: AppTextStyles.heading2.copyWith(
                            color: Colors.white,
                            fontSize: 22,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.subtitle,
                          style: AppTextStyles.bodySecondary.copyWith(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_slides.length, (i) {
            final active = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: active
                    ? AppColors.primary
                    : AppColors.textSecondary.withValues(alpha: 0.25),
              ),
            );
          }),
        ),
      ],
    );
  }
}

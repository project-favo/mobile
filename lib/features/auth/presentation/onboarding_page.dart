import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../routes/app_routes.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingContent> _pages = [
    OnboardingContent(
      title: 'Discover Products',
      description: 'Explore thousands of products and find what you\'re looking for.',
      illustration: Icons.shopping_bag_outlined,
      backgroundColor: AppColors.background,
      textColor: AppColors.textPrimary,
    ),
    OnboardingContent(
      title: 'Review & Share',
      description: 'Share your experiences and help others make better decisions.',
      illustration: Icons.rate_review_outlined,
      backgroundColor: AppColors.primary,
      textColor: Colors.white,
    ),
    OnboardingContent(
      title: 'Join FAVO',
      description: 'Create your account and start your journey with us today!',
      illustration: Icons.favorite_outline,
      backgroundColor: AppColors.background,
      textColor: AppColors.textPrimary,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    // Last page'de butonlar var, burada bir şey yapmıyoruz
  }

  void _skipToEnd() {
    _pageController.animateToPage(
      _pages.length - 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header with logo and skip
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xLarge,
                vertical: AppSpacing.medium,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo - FAVO text with logo-style font
                  Text(
                    'FAVO',
                    style: AppTextStyles.heading2.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      letterSpacing: 2,
                      shadows: [
                        Shadow(
                          color: AppColors.primary.withOpacity(0.3),
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  // Skip button
                  if (_currentPage < _pages.length - 1)
                    TextButton(
                      onPressed: _skipToEnd,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.medium,
                          vertical: AppSpacing.small,
                        ),
                      ),
                      child: Text(
                        'Skip',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Progress indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
              child: Row(
                children: List.generate(
                  _pages.length,
                  (index) => Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        right: index < _pages.length - 1 ? 8 : 0,
                      ),
                      decoration: BoxDecoration(
                        color: index <= _currentPage
                            ? AppColors.primary
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xLarge),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  final isLastPage = index == _pages.length - 1;
                  final isDarkBackground = page.backgroundColor == AppColors.primary;

                  return Container(
                    color: page.backgroundColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xLarge,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Illustration with decorative elements or logo for last page
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Background circle
                            Container(
                              width: 280,
                              height: 280,
                              decoration: BoxDecoration(
                                color: isDarkBackground
                                    ? Colors.white.withOpacity(0.15)
                                    : AppColors.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                            ),
                            // Main icon or logo
                            isLastPage
                                ? Image.asset(
                                    'assets/images/basket_removedbackground.png',
                                    width: 250,
                                    height: 250,
                                    fit: BoxFit.contain,
                                  )
                                : Icon(
                                    page.illustration,
                                    size: 140,
                                    color: isDarkBackground
                                        ? Colors.white
                                        : AppColors.primary,
                                  ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxLarge * 2),

                        // Title
                        Text(
                          page.title,
                          style: AppTextStyles.heading1.copyWith(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: page.textColor,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.large),

                        // Description
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.large,
                          ),
                          child: Text(
                            page.description,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 16,
                              color: isDarkBackground
                                  ? Colors.white.withOpacity(0.9)
                                  : AppColors.textSecondary,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                        if (isLastPage) ...[
                          const SizedBox(height: AppSpacing.xxLarge * 2),
                          // Login/Register buttons
                          AppButton(
                            text: 'Create Account',
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.register,
                              );
                            },
                            isLoading: false,
                          ),
                          const SizedBox(height: AppSpacing.large),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Already have an account? ',
                                style: AppTextStyles.body.copyWith(
                                  color: isDarkBackground
                                      ? Colors.white.withOpacity(0.9)
                                      : AppColors.textSecondary,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.login,
                                  );
                                },
                                child: Text(
                                  'Login',
                                  style: AppTextStyles.body.copyWith(
                                    color: isDarkBackground
                                        ? Colors.white
                                        : AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),

            // Next button - sağ altta minimal
            if (_currentPage < _pages.length - 1)
              Padding(
                padding: const EdgeInsets.only(
                  right: AppSpacing.xLarge,
                  bottom: AppSpacing.xLarge,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _nextPage,
                    child: Text(
                      'Next',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OnboardingContent {
  final String title;
  final String description;
  final IconData illustration;
  final Color backgroundColor;
  final Color textColor;

  OnboardingContent({
    required this.title,
    required this.description,
    required this.illustration,
    required this.backgroundColor,
    this.textColor = AppColors.textPrimary,
  });
}


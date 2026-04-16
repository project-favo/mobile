import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_spacing.dart';

/// Base shimmer effect widget
class SkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.textSecondary.withOpacity(0.1),
      highlightColor: AppColors.textSecondary.withOpacity(0.3),
      period: const Duration(milliseconds: 1500),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withOpacity(0.2),
          borderRadius: borderRadius ?? BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Product card skeleton
/// Liste sonu / sayfa sonu yükleme çubuğu.
class ListLoadMoreSkeleton extends StatelessWidget {
  const ListLoadMoreSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SkeletonLoader(
          width: 160,
          height: 10,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 8),
        SkeletonLoader(
          width: 100,
          height: 10,
          borderRadius: BorderRadius.circular(6),
        ),
      ],
    );
  }
}

class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: AppDecorations.productCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image skeleton
          SkeletonLoader(
            width: double.infinity,
            height: AppSpacing.productImageHeight,
            borderRadius: AppDecorations.cardRadius,
          ),
          const SizedBox(height: AppSpacing.medium),
          // Title and favorite
          Row(
            children: [
              Expanded(
                child: SkeletonLoader(
                  width: double.infinity,
                  height: 20,
                ),
              ),
              const SizedBox(width: 8),
              SkeletonLoader(
                width: 24,
                height: 24,
                borderRadius: BorderRadius.circular(12),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          // Category
          SkeletonLoader(
            width: 80,
            height: 14,
          ),
          const SizedBox(height: AppSpacing.medium),
          // Stars
          Row(
            children: List.generate(
              5,
              (index) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SkeletonLoader(
                  width: 16,
                  height: 16,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Description
          SkeletonLoader(
            width: double.infinity,
            height: 14,
          ),
        ],
      ),
    );
  }
}

/// Top product card skeleton
class TopProductCardSkeleton extends StatelessWidget {
  const TopProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 240,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image skeleton
          Padding(
            padding: const EdgeInsets.all(AppSpacing.medium),
            child: SkeletonLoader(
              width: double.infinity,
              height: 120,
              borderRadius: AppDecorations.cardRadius,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(
                  width: 100,
                  height: 16,
                ),
                const SizedBox(height: 4),
                SkeletonLoader(
                  width: 60,
                  height: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Review card skeleton
/// Arama sayfası ilk yükleme iskeleti.
class SearchPageBodySkeleton extends StatelessWidget {
  const SearchPageBodySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonLoader(
            width: double.infinity,
            height: 52,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(height: AppSpacing.xLarge),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.xLarge,
                mainAxisSpacing: AppSpacing.xLarge,
                childAspectRatio: 0.6,
              ),
              itemCount: 6,
              itemBuilder: (_, __) => const ProductCardSkeleton(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bildirim satırı iskeleti.
class NotificationTileSkeleton extends StatelessWidget {
  const NotificationTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xLarge,
        vertical: AppSpacing.small,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLoader(
            width: 44,
            height: 44,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(
                  width: double.infinity,
                  height: 14,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 8),
                SkeletonLoader(
                  width: 180,
                  height: 12,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Takip listesi kullanıcı satırı iskeleti.
/// Karşılaştırma — ürün seç listesi satırı.
class CompareProductRowSkeleton extends StatelessWidget {
  const CompareProductRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.medium),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Row(
            children: [
              SkeletonLoader(
                width: 64,
                height: 64,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: AppSpacing.xLarge),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(
                      width: double.infinity,
                      height: 16,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    const SizedBox(height: 8),
                    SkeletonLoader(
                      width: 120,
                      height: 12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
              ),
              SkeletonLoader(
                width: 24,
                height: 24,
                borderRadius: BorderRadius.circular(6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FollowUserRowSkeleton extends StatelessWidget {
  const FollowUserRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.large),
      child: Row(
        children: [
          SkeletonLoader(
            width: 48,
            height: 48,
            borderRadius: BorderRadius.circular(24),
          ),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(width: 140, height: 16),
                const SizedBox(height: 6),
                SkeletonLoader(width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewCardSkeleton extends StatelessWidget {
  const ReviewCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: AppDecorations.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info
          Row(
            children: [
              SkeletonLoader(
                width: 100,
                height: 16,
              ),
              const SizedBox(width: 8),
              SkeletonLoader(
                width: 60,
                height: 14,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          // Stars
          Row(
            children: List.generate(
              5,
              (index) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SkeletonLoader(
                  width: 20,
                  height: 20,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.small),
          // Content
          SkeletonLoader(
            width: double.infinity,
            height: 16,
          ),
          const SizedBox(height: 4),
          SkeletonLoader(
            width: double.infinity,
            height: 16,
          ),
          const SizedBox(height: 4),
          SkeletonLoader(
            width: 200,
            height: 16,
          ),
          const SizedBox(height: AppSpacing.medium),
          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SkeletonLoader(
                width: 60,
                height: 24,
                borderRadius: BorderRadius.circular(12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


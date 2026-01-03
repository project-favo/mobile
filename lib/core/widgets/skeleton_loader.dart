import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_colors.dart';
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
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image skeleton
          SkeletonLoader(
            width: double.infinity,
            height: AppSpacing.productImageHeight,
            borderRadius: BorderRadius.circular(12),
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
      width: 120,
      height: 170,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image skeleton
          SkeletonLoader(
            width: 120,
            height: 120,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
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
class ReviewCardSkeleton extends StatelessWidget {
  const ReviewCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
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


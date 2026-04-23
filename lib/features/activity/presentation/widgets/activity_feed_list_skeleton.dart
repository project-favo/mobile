import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeleton_loader.dart';

/// İlk yükleme / pull-to-refresh ile uyumlu: [ActivityFeedRow] satır hizası.
class ActivityFeedListSkeleton extends StatelessWidget {
  const ActivityFeedListSkeleton({super.key, this.scrollController});

  final ScrollController? scrollController;

  static const _dividerAlpha = 0.12;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4),
      itemCount: 9,
      separatorBuilder:
          (_, __) => Divider(
            height: 1,
            thickness: 1,
            color: AppColors.textSecondary.withValues(alpha: _dividerAlpha),
          ),
      itemBuilder: (context, index) {
        final showThumb = index % 3 != 1;
        final line2Width = index % 2 == 0 ? 220.0 : 150.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 14),
              ClipOval(
                child: SkeletonLoader(
                  width: 40,
                  height: 40,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SkeletonLoader(
                            width: double.infinity,
                            height: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SkeletonLoader(
                          width: 40,
                          height: 12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SkeletonLoader(
                      width: line2Width,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              if (showThumb) ...[
                const SizedBox(width: 10),
                SkeletonLoader(
                  width: 44,
                  height: 56,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Infinite scroll son satır iskeleti.
class ActivityFeedLoadMoreSkeleton extends StatelessWidget {
  const ActivityFeedLoadMoreSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipOval(
            child: SkeletonLoader(
              width: 36,
              height: 36,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SkeletonLoader(
              width: double.infinity,
              height: 14,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

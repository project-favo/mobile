import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';

class ReviewCard extends StatelessWidget {
  final String username;
  final String content;
  final int rating;
  final bool isSponsored;
  final int likeCount;
  final bool isLiked;
  final VoidCallback? onLikeTap;
  final VoidCallback? onTap;

  const ReviewCard({
    super.key,
    required this.username,
    required this.content,
    required this.rating,
    this.isSponsored = false,
    this.likeCount = 0,
    this.isLiked = false,
    this.onLikeTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.large),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // Sponsored review'lar için primary border, diğerleri için koyu gri veya border yok
          border: isSponsored
              ? Border.all(color: AppColors.primary, width: 2)
              : Border.all(color: AppColors.border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// USER + TAG
                  Row(
                    children: [
                      Text(
                        username,
                        style: AppTextStyles.bodyBold.copyWith(
                          decoration: TextDecoration.none,
                        ),
                      ),
                      if (isSponsored)
                        Text(
                          "  Sponsored",
                          style: AppTextStyles.chip.copyWith(
                            color: AppColors.primary,
                            decoration: TextDecoration.none,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.small),

                  /// STARS
                  Row(
                    children: [
                      ...List.generate(
                        5,
                        (i) => Icon(
                          Icons.star,
                          size: 18,
                          color: i < rating ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "($rating/5)",
                        style: AppTextStyles.bodySmall.copyWith(
                          decoration: TextDecoration.none,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.small),

                  /// TEXT - Max 3 lines with ellipsis
                  Text(
                    content,
                    style: AppTextStyles.heading3.copyWith(
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.medium),

                  /// LIKE / REPORT
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: onLikeTap,
                        child: Row(
                          children: [
                            Icon(
                              isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                              size: 20,
                              color: isLiked ? AppColors.primary : AppColors.textPrimary,
                            ),
                            if (likeCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                likeCount.toString(),
                                style: AppTextStyles.bodySmall.copyWith(
                                  decoration: TextDecoration.none,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.flag_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Arrow icon on the right
            const SizedBox(width: AppSpacing.small),
            Icon(
              Icons.chevron_right,
              size: 24,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import 'review_delete_action.dart';
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
  final VoidCallback? onUsernameTap;
  final bool showChatIcon;
  final VoidCallback? onChatTap;
  final VoidCallback? onReportTap;
  final VoidCallback? onDeleteTap;
  final bool isCurrentUser;
  final String? reviewDateLabel;

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
    this.onUsernameTap,
    this.showChatIcon = false,
    this.onChatTap,
    this.onReportTap,
    this.onDeleteTap,
    this.isCurrentUser = false,
    this.reviewDateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.large),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: isSponsored
              ? Border.all(color: AppColors.primary, width: 2)
              : Border.all(color: AppColors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// USER + TAG
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: onUsernameTap,
                        child: Text(
                          username,
                          style: AppTextStyles.body.copyWith(
                            color:
                                isCurrentUser
                                    ? AppColors.error
                                    : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
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
                ),
                if (reviewDateLabel != null && reviewDateLabel!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.small),
                    child: Text(
                      reviewDateLabel!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
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
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.35,
                decoration: TextDecoration.none,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.medium),

            /// ACTION ROW: grouped actions + detail arrow
            Row(
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.small,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: onLikeTap,
                        child: Row(
                          children: [
                            Icon(
                              Icons.thumb_up_alt_outlined,
                              size: 18,
                              color:
                                  isLiked
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              likeCount.toString(),
                              style: AppTextStyles.bodySmall.copyWith(
                                color:
                                    isLiked
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onDeleteTap != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 14,
                          color: AppColors.border,
                        ),
                        const SizedBox(width: 10),
                        ReviewInlineDeleteIcon(onTap: onDeleteTap!),
                      ],
                      if (onReportTap != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 14,
                          color: AppColors.border,
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: onReportTap,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.outlined_flag,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (showChatIcon) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 14,
                          color: AppColors.border,
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: onChatTap,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.small),
                // Detail arrow (bottom-right)
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

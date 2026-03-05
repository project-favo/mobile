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
  final bool showChatIcon;
  final VoidCallback? onChatTap;

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
    this.showChatIcon = false,
    this.onChatTap,
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

            /// ACTION ROW: like, report, chat + detail arrow
            Row(
              children: [
                // Like
                GestureDetector(
                  onTap: onLikeTap,
                  child: Row(
                    children: [
                      Icon(
                        isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                        size: 22,
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
                const SizedBox(width: 16),
                // Report
                Icon(
                  Icons.flag_outlined,
                  size: 22,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 16),
                // Chat
                if (showChatIcon)
                  InkWell(
                    onTap: onChatTap,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        size: 22,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                const Spacer(),
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

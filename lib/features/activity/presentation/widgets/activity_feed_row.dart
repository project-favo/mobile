import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../domain/activity_models.dart';
import '../../domain/activity_type.dart';
import '../../utils/relative_time.dart';

class ActivityFeedRow extends StatelessWidget {
  const ActivityFeedRow({
    super.key,
    required this.item,
    required this.following,
    required this.onToggleFollow,
    required this.onOpen,
    this.onUserTap,
  });

  final ActivityItem item;
  final bool following;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpen;
  /// Kullanıcının pp/ismine tıklanınca çağrılır (null ise devre dışı).
  final VoidCallback? onUserTap;

  @override
  Widget build(BuildContext context) {
    final time = formatActivityRelativeTime(item.timestamp);
    final showFollow =
        item.type == ActivityType.follow && item.user.id.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!item.isRead)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 4),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              else
                const SizedBox(width: 2),
              GestureDetector(
                onTap: onUserTap,
                behavior: HitTestBehavior.opaque,
                child: ProfileAvatar(
                  key: ValueKey(
                    'avatar_${item.user.id}_${item.user.avatarUrl ?? ''}',
                  ),
                  radius: 22,
                  imageUrl: item.user.avatarUrl,
                  fallbackInitial: item.user.username.isNotEmpty
                      ? item.user.username
                      : '?',
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
                        Expanded(child: _buildLineText()),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: AppTextStyles.bodySecondary.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                    if (showFollow) ...[
                      const SizedBox(height: 10),
                      _FollowChip(
                        following: following,
                        onTap: onToggleFollow,
                      ),
                    ],
                  ],
                ),
              ),
              if (_showThumbnail) ...[
                const SizedBox(width: 12),
                _ContentThumb(
                  url: item.targetContent?.thumbnailUrl,
                  title: item.targetContent?.title ?? '',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _showThumbnail {
    final hasImage = (item.targetContent?.thumbnailUrl ?? '').trim().isNotEmpty;
    final pid = (item.targetContent?.productId ?? '').trim().isNotEmpty;
    if (!hasImage && !pid) return false;
    return item.type == ActivityType.like ||
        item.type == ActivityType.comment ||
        item.type == ActivityType.review;
  }

  Widget _buildLineText() {
    final line = item.lineText.trim();
    final u = item.user.username;

    final baseStyle = AppTextStyles.body.copyWith(
      color: AppColors.textPrimary,
      fontSize: 15,
      height: 1.4,
      fontWeight: FontWeight.w400,
    );

    if (u.isNotEmpty && line.startsWith(u)) {
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(
              text: u,
              style: baseStyle.copyWith(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: line.substring(u.length),
              style: baseStyle.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      line,
      style: baseStyle,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _FollowChip extends StatelessWidget {
  const _FollowChip({
    required this.following,
    required this.onTap,
  });

  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: following
                ? AppColors.textPrimary.withValues(alpha: 0.05)
                : AppColors.surface,
            border: Border.all(
              color: following
                  ? AppColors.border.withValues(alpha: 0.65)
                  : AppColors.primary.withValues(alpha: 0.55),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            following ? 'Following' : 'Follow',
            style: TextStyle(
              color: following
                  ? AppColors.textSecondary
                  : AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentThumb extends StatelessWidget {
  const _ContentThumb({
    required this.url,
    required this.title,
  });

  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: url != null && url!.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.all(4),
                child: Image.network(
                  url!,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                    if (wasSynchronouslyLoaded || frame != null) return child;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: frame == null ? _placeholder(context) : child,
                    );
                  },
                  errorBuilder: (_, __, ___) => _placeholder(context),
                ),
              )
            : _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            title.isNotEmpty
                ? (title.length >= 2 ? title.substring(0, 2) : title)
                : '·',
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

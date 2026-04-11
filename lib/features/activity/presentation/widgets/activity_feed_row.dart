import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
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
  });

  final ActivityItem item;
  final bool following;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpen;

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!item.isRead)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
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
                const SizedBox(width: 14),
              _Avatar(user: item.user),
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
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
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
                const SizedBox(width: 10),
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
    final pid = item.targetContent?.productId;
    if (pid == null || pid.isEmpty) return false;
    return item.type == ActivityType.like ||
        item.type == ActivityType.comment ||
        item.type == ActivityType.review;
  }

  Widget _buildLineText() {
    final line = item.lineText.trim();
    final u = item.user.username;

    final baseStyle = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 15,
      height: 1.35,
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
            TextSpan(text: line.substring(u.length)),
          ],
        ),
      );
    }

    return Text(line, style: baseStyle);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final ActivityUser user;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.border.withValues(alpha: 0.35),
      backgroundImage:
          url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: url == null || url.isEmpty
          ? Text(
              user.username.isNotEmpty
                  ? user.username[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            )
          : null,
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: following
                  ? AppColors.textSecondary.withValues(alpha: 0.45)
                  : AppColors.primary,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            following ? 'Following' : 'Follow',
            style: TextStyle(
              color: following
                  ? AppColors.textSecondary
                  : AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 44,
        height: 56,
        child: url != null && url!.isNotEmpty
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(context),
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

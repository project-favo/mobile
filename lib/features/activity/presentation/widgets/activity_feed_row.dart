import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Okunmamış nokta veya küçük boşluk
              if (!item.isRead)
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 6),
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
                const SizedBox(width: 6),
              GestureDetector(
                onTap: onUserTap,
                behavior: HitTestBehavior.opaque,
                child: ProfileAvatar(
                  key: ValueKey('avatar_${item.user.id}'),
                  radius: 20,
                  imageUrl: item.user.avatarUrl,
                  fallbackInitial: item.user.username.isNotEmpty
                      ? item.user.username
                      : '?',
                ),
              ),
              const SizedBox(width: 10),
              // İçerik: metin + follow chip
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLineText(),
                    if (showFollow) ...[
                      const SizedBox(height: 8),
                      _FollowChip(
                        following: following,
                        onTap: onToggleFollow,
                      ),
                    ],
                  ],
                ),
              ),
              // Thumbnail (varsa)
              if (_showThumbnail) ...[
                const SizedBox(width: 8),
                _ContentThumb(
                  url: item.targetContent?.thumbnailUrl,
                  title: item.targetContent?.title ?? '',
                ),
              ],
              // Saat — her zaman sağ üstte, thumbnail'dan bağımsız
              const SizedBox(width: 8),
              Text(
                time,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
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

    return Text(
      line,
      style: baseStyle,
      maxLines: 3,
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
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: url != null && url!.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.all(3),
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

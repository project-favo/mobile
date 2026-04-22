import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/notifications/notification_realtime_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/main_bottom_nav_items.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../domain/activity_models.dart';
import '../domain/activity_type.dart';
import '../../auth/presentation/home_page.dart';
import '../../auth/presentation/friend_feed_page.dart';
import '../../auth/presentation/profile/pages/profile_page.dart';
import '../../auth/presentation/profile/pages/user_profile_page.dart';
import '../../auth/presentation/review/pages/review_page.dart';
import '../../auth/presentation/search_page.dart';
import 'activity_controller.dart';
import 'widgets/activity_feed_row.dart';

/// Activity feed backed by the notifications API (app color palette).
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with SingleTickerProviderStateMixin {
  late final ActivityController _controller;
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<NotificationPushEvent>? _pushSub;

  Route<T> _instantRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  BottomNavigationBar _buildBottomNavigationBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 3,
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      onTap: (index) {
        if (index == 3) return;
        if (index == 1) {
          Navigator.pushReplacement(
            context,
            _instantRoute(const FriendFeedPage()),
          );
          return;
        }
        if (index == 0) {
          Navigator.pushReplacement(context, _instantRoute(const SearchPage()));
          return;
        }
        if (index == 2) {
          Navigator.pushReplacement(context, _instantRoute(const HomePage()));
          return;
        }
        if (index == 4) {
          Navigator.pushReplacement(
            context,
            _instantRoute(const ProfilePage()),
          );
        }
      },
      items: MainBottomNavItems.barItems,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _controller = ActivityController();
    NotificationRealtimeService.instance.attach();
    _pushSub = NotificationRealtimeService.instance.pushStream.listen(
      _onRealtimePush,
    );
    _scrollController.addListener(_onScroll);
    _controller.hydrateFromCache();
    unawaited(_bootstrapActivity());
  }

  Future<void> _bootstrapActivity() async {
    await _controller.loadFirstPage();
    if (!mounted) return;
    if (_controller.errorMessage == null) {
      await _controller.markEntireFeedViewed();
    }
    if (mounted) {
      await NotificationRealtimeService.instance.refreshUnread();
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _pushSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    NotificationRealtimeService.instance.detach();
    _controller.dispose();
    super.dispose();
  }

  List<ActivityItem> _filteredItems() {
    final all = _controller.items;
    switch (_tabController.index) {
      case 1:
        return all.where((e) {
          final t = e.lineText.toLowerCase();
          return e.type == ActivityType.follow ||
              t.contains('followed you') ||
              t.contains('started following you');
        }).toList();
      case 2:
        return all.where((e) {
          final t = e.lineText.toLowerCase();
          return e.type == ActivityType.like &&
              (t.contains('your review') || t.contains('liked your review'));
        }).toList();
      case 3:
        return all.where((e) => e.type == ActivityType.review).toList();
      default:
        return all;
    }
  }

  void _onRealtimePush(NotificationPushEvent e) {
    final n = e.notification;
    if (n == null || !mounted) return;
    _controller.prependFromPush(n);
    unawaited(NotificationRealtimeService.instance.refreshUnread());
  }

  void _onScroll() {
    if (_controller.loadingMore ||
        _controller.loadingFirst ||
        !_controller.hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      unawaited(_controller.loadMore());
    }
  }

  Future<void> _onOpenItem(BuildContext context, ActivityItem item) async {
    if (!item.isRead) {
      try {
        await _controller.markRead(item.id);
        if (mounted) {
          await NotificationRealtimeService.instance.refreshUnread();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ErrorHandler.getUserFriendlyMessage(e)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }

    if (!context.mounted) return;

    switch (item.type) {
      case ActivityType.follow:
        if (item.user.id.isEmpty) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder:
                (_) => UserProfilePage(
                  userId: item.user.id,
                  userName: item.user.username,
                  profileImageUrl: item.user.avatarUrl,
                ),
          ),
        );
        break;
      case ActivityType.like:
      case ActivityType.comment:
      case ActivityType.review:
        final pid = item.targetContent?.productId;
        if (pid != null && pid.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder:
                  (_) => ReviewPage(
                    productId: pid,
                    productName: item.targetContent?.title,
                  ),
            ),
          );
        }
        break;
    }
  }

  Future<void> _onToggleFollow(BuildContext context, String userId) async {
    try {
      await _controller.toggleFollow(userId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserFriendlyMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    await _controller.loadFirstPage();
    if (mounted && _controller.errorMessage == null) {
      await _controller.markEntireFeedViewed();
    }
    if (mounted) {
      await NotificationRealtimeService.instance.refreshUnread();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background.withValues(alpha: 0.96),
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        toolbarHeight: AppSpacing.toolbarHeight,
        centerTitle: true,
        title: Text(
          'Notifications',
          style: AppTextStyles.heading2.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  indicator: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textSecondary,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  tabs: const [
                    Tab(text: 'All'),
                    Tab(text: 'Follow'),
                    Tab(text: 'Likes'),
                    Tab(text: 'Reviews'),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.textSecondary.withValues(alpha: 0.12),
              ),
            ],
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.loadingFirst) {
            return _ActivityFeedSkeletonList(controller: _scrollController);
          }

          if (_controller.errorMessage != null) {
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _onRefresh,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xLarge),
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.error_outline, size: 56, color: AppColors.error),
                  const SizedBox(height: AppSpacing.large),
                  Text(
                    _controller.errorMessage!,
                    style: AppTextStyles.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Center(
                    child: TextButton(
                      onPressed: _onRefresh,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            );
          }

          final visible = _filteredItems();
          if (_controller.items.isEmpty) {
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _onRefresh,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xLarge),
                children: [
                  const SizedBox(height: 100),
                  Icon(
                    Icons.notifications_none_outlined,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Text(
                    'No activity yet',
                    style: AppTextStyles.bodySecondary,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          if (visible.isEmpty) {
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _onRefresh,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xLarge),
                children: [
                  const SizedBox(height: 100),
                  Icon(
                    Icons.filter_list_off_outlined,
                    size: 56,
                    color: AppColors.textSecondary.withValues(alpha: 0.45),
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Text(
                    'Nothing in this category',
                    style: AppTextStyles.bodySecondary,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _onRefresh,
            child: ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
              itemCount: visible.length + (_controller.loadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index >= visible.length) {
                  return const _ActivityLoadMoreSkeleton();
                }
                final item = visible[index];
                return Container(
                  key: ValueKey(item.id),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.7),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ActivityFeedRow(
                    key: ValueKey('row_${item.id}'),
                    item: item,
                    following: _controller.isFollowingUser(item.user.id),
                    onToggleFollow:
                        () => _onToggleFollow(context, item.user.id),
                    onOpen: () => _onOpenItem(context, item),
                  ),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}

/// İlk yükleme: [ActivityFeedRow] ile aynı hizalama (avatar + metin + isteğe bağlı thumb).
class _ActivityFeedSkeletonList extends StatelessWidget {
  const _ActivityFeedSkeletonList({required this.controller});

  final ScrollController controller;

  static const _dividerAlpha = 0.12;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
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

class _ActivityLoadMoreSkeleton extends StatelessWidget {
  const _ActivityLoadMoreSkeleton();

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

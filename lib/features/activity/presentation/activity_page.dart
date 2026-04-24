import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/cache/activity_memory_cache.dart';
import '../../../core/cache/following_id_set_cache.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../../../core/notifications/notification_realtime_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/config/list_paging.dart';
import '../../../core/widgets/paged_navigation_bar.dart';
import '../../../core/utils/session_helper.dart';
import '../../../core/utils/user_profile_navigation.dart';
import '../../../core/widgets/main_bottom_nav_items.dart';
import '../domain/activity_models.dart';
import '../domain/activity_type.dart';
import '../../auth/presentation/home_page.dart';
import '../../auth/presentation/friend_feed_page.dart';
import '../../auth/presentation/profile/pages/profile_page.dart';
import '../../auth/presentation/review/pages/review_page.dart';
import '../../auth/data/repositories/interaction_repository.dart';
import '../../auth/data/services/auth_service.dart';
import '../../auth/presentation/search_page.dart';
import '../../../core/cache/product_memory_cache.dart';
import '../../auth/data/models/product_dto.dart';
import '../../auth/data/models/tag_dto.dart';
import 'activity_controller.dart';
import 'widgets/activity_feed_list_skeleton.dart';
import 'widgets/activity_feed_row.dart';

/// Activity feed backed by the notifications API (app color palette).
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with SingleTickerProviderStateMixin, RouteAware {
  late final ActivityController _controller;
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  /// Her sekme için ayrı sayfa (her sayfada en fazla [kStandardListPageSize] satır).
  final List<int> _pageInTab = [0, 0, 0, 0];
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
      selectedFontSize: 0,
      unselectedFontSize: 0,
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
    unawaited(
      FollowingIdSetCache.instance.ensureLoaded(
        InteractionRepository(),
        AuthService(),
        SessionHelper(),
      ),
    );
    unawaited(_bootstrapActivity());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route is PageRoute<dynamic>) {
        appRouteObserver.subscribe(this, route);
      }
    });
  }

  @override
  void didPopNext() {
    unawaited(_refreshOnReturn());
  }

  Future<void> _refreshOnReturn() async {
    await _controller.loadFirstPage();
    if (!mounted) return;
    await NotificationRealtimeService.instance.refreshUnread();
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
    setState(() {
      _pageInTab[_tabController.index] = 0;
    });
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    ActivityMemoryCache.instance.clear();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _pushSub?.cancel();
    _scrollController.dispose();
    NotificationRealtimeService.instance.detach();
    _controller.dispose();
    super.dispose();
  }

  List<ActivityItem> _filteredItems() =>
      _filterForTabIndex(_controller.items, _tabController.index);

  void _onRealtimePush(NotificationPushEvent e) {
    final n = e.notification;
    if (n == null || !mounted) return;
    unawaited(_controller.prependFromPush(n));
    unawaited(NotificationRealtimeService.instance.refreshUnread());
  }

  List<ActivityItem> _filterForTabIndex(List<ActivityItem> all, int tab) {
    switch (tab) {
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

  List<ActivityItem> _visiblePageForCurrentTab() {
    final filtered = _filteredItems();
    if (filtered.isEmpty) return const [];
    final tab = _tabController.index;
    var p = _pageInTab[tab];
    final maxP = math.max(0, ((filtered.length - 1) ~/ kStandardListPageSize));
    if (p > maxP) p = maxP;
    final start = p * kStandardListPageSize;
    if (start >= filtered.length) return const [];
    final end = math.min(start + kStandardListPageSize, filtered.length);
    return filtered.sublist(start, end);
  }

  int _tabDisplayPage1Based() {
    final filtered = _filteredItems();
    if (filtered.isEmpty) return 1;
    final tab = _tabController.index;
    var p = _pageInTab[tab];
    final maxP = math.max(0, ((filtered.length - 1) ~/ kStandardListPageSize));
    if (p > maxP) p = maxP;
    return p + 1;
  }

  int _tabTotalPages() {
    final n = _filteredItems().length;
    if (n == 0) return 1;
    return ((n - 1) ~/ kStandardListPageSize) + 1;
  }

  bool _canGoNextActivity() {
    final tab = _tabController.index;
    final f = _filterForTabIndex(_controller.items, tab);
    if (f.isEmpty) return false;
    final p = _pageInTab[tab];
    if ((p + 1) * kStandardListPageSize < f.length) return true;
    return _controller.hasMore;
  }

  bool _canGoPrevActivity() => _pageInTab[_tabController.index] > 0;

  Future<void> _goNextActivity() async {
    if (!_canGoNextActivity()) return;
    final tab = _tabController.index;
    var p = _pageInTab[tab];
    var f = _filterForTabIndex(_controller.items, tab);
    if ((p + 1) * kStandardListPageSize < f.length) {
      setState(() => _pageInTab[tab] = p + 1);
      return;
    }
    if (!_controller.hasMore) return;
    var guard = 40;
    while (_controller.hasMore && guard-- > 0) {
      final beforeLen = _controller.items.length;
      await _controller.loadMore();
      if (!mounted) return;
      f = _filterForTabIndex(_controller.items, tab);
      if ((p + 1) * kStandardListPageSize < f.length) {
        setState(() => _pageInTab[tab] = p + 1);
        return;
      }
      if (_controller.items.length == beforeLen) break;
    }
  }

  void _goPrevActivity() {
    final t = _tabController.index;
    if (_pageInTab[t] <= 0) return;
    setState(() => _pageInTab[t]--);
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
        openUserProfileIfActive(
          context,
          userId: item.user.id,
          userName: item.user.username,
          profileImageUrl: item.user.avatarUrl,
        );
        break;
      case ActivityType.like:
      case ActivityType.comment:
      case ActivityType.review:
        final pid = item.targetContent?.productId;
        if (pid != null && pid.isNotEmpty) {
          if (ProductMemoryCache.instance.peek(pid) == null) {
            final thumb = item.targetContent?.thumbnailUrl ?? '';
            final name  = item.targetContent?.title ?? '';
            if (thumb.isNotEmpty) {
              ProductMemoryCache.instance.remember(ProductDto(
                id: pid,
                name: name,
                imageURL: thumb,
                tag: TagDto(id: '', name: ''),
              ));
            }
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReviewPage(
                productId: pid,
                productName: item.targetContent?.title,
              ),
            ),
          );
        }
        break;
    }
  }

  void _onUserTap(BuildContext context, ActivityItem item) {
    if (item.user.id.isEmpty) return;
    openUserProfileIfActive(
      context,
      userId: item.user.id,
      userName: item.user.username,
      profileImageUrl: item.user.avatarUrl,
    );
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
            return ActivityFeedListSkeleton(
              scrollController: _scrollController,
            );
          }

          if (_controller.errorMessage != null) {
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _onRefresh,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
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

          final filtered = _filteredItems();
          if (_controller.items.isEmpty) {
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _onRefresh,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
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

          if (filtered.isEmpty) {
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _onRefresh,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
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

          final pageItems = _visiblePageForCurrentTab();
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _onRefresh,
            child: ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
              itemCount: pageItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = pageItems[index];
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
                    onToggleFollow: () => _onToggleFollow(context, item.user.id),
                    onOpen: () => _onOpenItem(context, item),
                    onUserTap: () => _onUserTap(context, item),
                  ),
                );
              },
            ),
                ),
              ),
              if (filtered.isNotEmpty)
                PagedNavigationBar(
                  currentPage1Based: _tabDisplayPage1Based(),
                  totalPages: _tabTotalPages(),
                  canGoPrevious: _canGoPrevActivity(),
                  canGoNext: _canGoNextActivity(),
                  isLoadingNext: _controller.loadingMore,
                  onPrevious: _goPrevActivity,
                  onNext: () {
                    unawaited(_goNextActivity());
                  },
                  showTopDivider: true,
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/cache/activity_memory_cache.dart';
import '../../../core/cache/following_id_set_cache.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../../../core/notifications/notification_realtime_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/routes/custom_page_transitions.dart';
import '../../../core/utils/content_availability_messages.dart';
import '../../../core/utils/content_unavailable_dialog.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/exceptions.dart';
import '../../../core/widgets/feed_screen_tab_bar.dart';
import '../../../core/utils/session_helper.dart';
import '../../../core/utils/user_profile_navigation.dart';
import '../../../core/widgets/main_bottom_nav_items.dart';
import '../domain/activity_models.dart';
import '../domain/activity_type.dart';
import '../../auth/presentation/home_page.dart';
import '../../auth/presentation/friend_feed_page.dart';
import '../../auth/presentation/profile/pages/profile_page.dart';
import '../../auth/presentation/review/pages/review_detail_page.dart';
import '../../auth/presentation/review/pages/review_page.dart';
import '../../auth/data/repositories/interaction_repository.dart';
import '../../auth/data/repositories/product_repository.dart';
import '../../auth/data/repositories/review_repository.dart';
import '../../auth/data/services/auth_service.dart';
import '../../auth/presentation/search_page.dart';
import '../../../core/cache/product_memory_cache.dart';
import '../../auth/data/models/product_dto.dart';
import '../../auth/data/models/tag_dto.dart';
import 'activity_controller.dart';
import 'widgets/activity_feed_list_skeleton.dart';
import 'widgets/activity_feed_row.dart';

bool _activitySuggestProductOrReviewGone(Object e) {
  if (e is ReviewNotAvailableException || e is ProductNotAvailableException) {
    return true;
  }
  if (e is DioException) {
    final c = e.response?.statusCode;
    if (c != null && c >= 400 && c < 500 && c != 429) {
      return true;
    }
  }
  final s = e.toString().toLowerCase();
  return s.contains('reviewnotavailable') ||
      s.contains('productnotavailable') ||
      s.contains('not available') ||
      s.contains('no longer') ||
      s.contains('unavailable') ||
      s.contains('removed from');
}

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
    if (mounted) _scheduleActivityPrefetchIfNeeded();
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
    if (mounted) _scheduleActivityPrefetchIfNeeded();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleActivityPrefetchIfNeeded();
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

  void _maybeLoadMoreActivity(ScrollMetrics metrics) {
    if (_controller.loadingMore || _controller.loadingFirst) return;
    if (!_controller.hasMore) return;
    if (metrics.maxScrollExtent <= 0) return;
    if (metrics.pixels < metrics.maxScrollExtent - 360) return;
    unawaited(_controller.loadMore());
  }

  void _scheduleActivityPrefetchIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.loadingMore ||
          _controller.loadingFirst ||
          !_controller.hasMore) {
        return;
      }
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent > 72) return;
      unawaited(_controller.loadMore());
    });
  }

  Future<void> _openProductReviewPageFromActivity(
    BuildContext context,
    ActivityItem item,
  ) async {
    final pid = item.targetContent?.productId;
    if (pid == null || pid.isEmpty) return;
    if (ProductMemoryCache.instance.peek(pid) == null) {
      final thumb = item.targetContent?.thumbnailUrl ?? '';
      final name = item.targetContent?.title ?? '';
      if (thumb.isNotEmpty) {
        ProductMemoryCache.instance.remember(
          ProductDto(
            id: pid,
            name: name,
            imageURL: thumb,
            tag: TagDto(id: '', name: ''),
          ),
        );
      }
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReviewPage(
          productId: pid,
          productName: item.targetContent?.title,
        ),
      ),
    );
  }

  Future<void> _showProductOrReviewUnavailableDialog(BuildContext context) async {
    if (!context.mounted) return;
    await showContentUnavailableDialog(
      context,
      title: kTitleProductOrReviewUnavailable,
      message: kMessageProductOrReviewNoLongerAvailable,
      onContinue: () async {},
    );
  }

  Future<void> _openReviewDetailFromId(
    BuildContext context,
    String reviewId,
  ) async {
    try {
      final token = await SessionHelper().ensureSession();
      if (!context.mounted) return;
      final review = await ReviewRepository().getReviewById(
        reviewId,
        firebaseIdToken: token,
      );
      final product = await ProductRepository().getProductById(
        review.productId,
        firebaseIdToken: token,
        bypassCache: true,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        SlideRightRoute(
          page: ReviewDetailPage(
            review: review,
            product: product,
          ),
        ),
      );
    } on ReviewNotAvailableException {
      if (context.mounted) {
        await _showProductOrReviewUnavailableDialog(context);
      }
    } on ProductNotAvailableException {
      if (context.mounted) {
        await _showProductOrReviewUnavailableDialog(context);
      }
    } catch (e) {
      if (!context.mounted) return;
      if (_activitySuggestProductOrReviewGone(e)) {
        await _showProductOrReviewUnavailableDialog(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserFriendlyMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
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
        openUserProfileIfActive(
          context,
          userId: item.user.id,
          userName: item.user.username,
          profileImageUrl: item.user.avatarUrl,
        );
        break;
      case ActivityType.like:
        final rid = item.targetContent?.reviewId?.trim();
        if (rid != null && rid.isNotEmpty) {
          await _openReviewDetailFromId(context, rid);
        } else {
          await _openProductReviewPageFromActivity(context, item);
        }
        break;
      case ActivityType.comment:
      case ActivityType.review:
        await _openProductReviewPageFromActivity(context, item);
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
    await _controller.loadFirstPage(flushRemoteListabilityCaches: true);
    if (mounted && _controller.errorMessage == null) {
      await _controller.markEntireFeedViewed();
    }
    if (mounted) {
      await NotificationRealtimeService.instance.refreshUnread();
      _scheduleActivityPrefetchIfNeeded();
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
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FeedScreenTabBar(
                controller: _tabController,
                tabLabels: const ['All', 'Follow', 'Likes', 'Reviews'],
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

          final tail =
              _controller.loadingMore && _controller.hasMore ? 1 : 0;
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _onRefresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification n) {
                if (n.metrics.axis == Axis.vertical &&
                    (n is ScrollUpdateNotification ||
                        n is ScrollEndNotification)) {
                  _maybeLoadMoreActivity(n.metrics);
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                itemCount: filtered.length + tail,
                itemBuilder: (context, index) {
                  if (index >= filtered.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    );
                  }
                  final item = filtered[index];
                  return Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                    child: Container(
                      key: ValueKey(item.id),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ActivityFeedRow(
                        key: ValueKey('row_${item.id}'),
                        item: item,
                        following: _controller.isFollowingUser(item.user.id),
                        onToggleFollow: () =>
                            _onToggleFollow(context, item.user.id),
                        onOpen: () => _onOpenItem(context, item),
                        onUserTap: () => _onUserTap(context, item),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}

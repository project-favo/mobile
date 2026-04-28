import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/cache/following_id_set_cache.dart';
import '../../../core/cache/friend_feed_memory_cache.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../../../core/cache/product_memory_cache.dart';
import '../data/models/product_dto.dart';
import '../data/models/tag_dto.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/load_profile_image_bytes.dart';
import '../../../core/config/list_paging.dart';
import '../data/utils/notification_remote_user_filter.dart';
import '../../../core/widgets/feed_screen_tab_bar.dart';
import '../../../core/utils/user_profile_navigation.dart';
import '../../../core/widgets/main_bottom_nav_items.dart';
import '../../../features/activity/data/friends_feed_activity_mapper.dart';
import '../../../features/activity/data/friends_feed_repository.dart';
import '../data/repositories/interaction_repository.dart';
import '../data/services/auth_service.dart';
import '../../../core/utils/in_flight_id_lock.dart';
import '../../../core/utils/session_helper.dart';
import '../../../features/activity/domain/activity_models.dart';
import '../../../features/activity/domain/activity_type.dart';
import '../../../features/activity/presentation/widgets/activity_feed_list_skeleton.dart';
import '../../../features/activity/presentation/widgets/activity_feed_row.dart';
import '../../../features/activity/presentation/activity_page.dart';
import 'home_page.dart';
import 'profile/pages/profile_page.dart';
import 'review/pages/review_page.dart';
import 'search_page.dart';

class FriendFeedPage extends StatefulWidget {
  const FriendFeedPage({super.key});

  @override
  State<FriendFeedPage> createState() => _FriendFeedPageState();
}

class _FriendFeedPageState extends State<FriendFeedPage>
    with SingleTickerProviderStateMixin, RouteAware {
  late final TabController _tabController;
  final List<ScrollController> _tabScrollControllers =
      List.generate(3, (_) => ScrollController());
  int _lastTabIndex = 0;
  final FriendsFeedRepository _repository = FriendsFeedRepository();
  final InteractionRepository _interactions = InteractionRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final Set<String> _followingIds = {};
  final InFlightIdLock _friendFeedFollowLock = InFlightIdLock();
  final List<ActivityItem> _items = [];

  int _page = 0;
  int _totalPages = 1;
  bool _loadingFirst = true;
  bool _loadingMore = false;
  String? _error;
  bool _loadFirstInFlight = false;

  Route<T> _instantRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final i = _tabController.index;
      if (i != _lastTabIndex) {
        _lastTabIndex = i;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_tabScrollControllers[i].hasClients) {
            _tabScrollControllers[i].jumpTo(0);
          }
          _scheduleFriendFeedPrefetchIfNeeded();
        });
      }
    });
    final warm = FriendFeedMemoryCache.instance.peek();
    if (warm != null && warm.items.isNotEmpty) {
      _items
        ..clear()
        ..addAll(warm.items);
      _page = warm.page;
      _totalPages = warm.totalPages;
      _loadingFirst = false;
      _prefetchItemVisuals(_items);
      _mergeFollowFromGlobalCache();
      unawaited(_syncFollowingForCurrentItems(refetchFollowingSet: true));
      unawaited(_loadFirst(background: true));
    } else {
      unawaited(
        FollowingIdSetCache.instance.ensureLoaded(
          _interactions,
          AuthService(),
          _sessionHelper,
        ),
      );
      unawaited(_loadFirst());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route is PageRoute<dynamic>) {
        appRouteObserver.subscribe(this, route);
      }
      if (_items.isNotEmpty) {
        _scheduleFriendFeedPrefetchIfNeeded();
      }
    });
  }

  @override
  void didPopNext() {
    unawaited(_loadFirst(
      background: _items.isNotEmpty,
      refreshUserListability: false,
    ));
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    FriendFeedMemoryCache.instance.clear();
    for (final c in _tabScrollControllers) {
      c.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  void _mergeFollowFromGlobalCache() {
    if (!FollowingIdSetCache.instance.isReady) return;
    for (final item in _items) {
      final id = item.user.id;
      if (id.isEmpty) continue;
      if (FollowingIdSetCache.instance.contains(id)) {
        _followingIds.add(id);
      } else {
        _followingIds.remove(id);
      }
    }
  }

  Future<void> _syncFollowingForCurrentItems({
    bool refetchFollowingSet = false,
  }) async {
    final token = await _sessionHelper.ensureSession();
    if (token == null) return;
    final ids = _items.map((e) => e.user.id).where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    try {
      await FollowingIdSetCache.instance.ensureLoaded(
        _interactions,
        AuthService(),
        _sessionHelper,
        force: refetchFollowingSet,
      );
      final my = FollowingIdSetCache.instance.snapshot;
      for (final id in ids) {
        if (my.contains(id)) {
          _followingIds.add(id);
        } else {
          _followingIds.remove(id);
        }
      }
    } catch (_) {
      for (final id in ids) {
        try {
          final f = await _interactions.isFollowing(token, id);
          if (f) {
            _followingIds.add(id);
          } else {
            _followingIds.remove(id);
          }
        } catch (_) {}
      }
    }
    if (mounted) setState(() {});
  }

  void _prefetchItemVisuals(Iterable<ActivityItem> items) {
    for (final item in items) {
      final avatar = item.user.avatarUrl;
      if (avatar != null && avatar.trim().isNotEmpty) {
        unawaited(loadProfileImageBytesFromRaw(avatar));
      }
      final thumb = item.targetContent?.thumbnailUrl;
      if (thumb != null && thumb.trim().isNotEmpty) {
        final stream = NetworkImage(thumb).resolve(const ImageConfiguration());
        late final ImageStreamListener listener;
        listener = ImageStreamListener(
          (_, __) => stream.removeListener(listener),
          onError: (_, __) => stream.removeListener(listener),
        );
        stream.addListener(listener);
      }
    }
  }

  Future<void> _loadFirst({
    bool background = false,
    bool refreshUserListability = false,
  }) async {
    if (_loadFirstInFlight) return;
    _loadFirstInFlight = true;
    if (!background) {
      setState(() {
        _loadingFirst = true;
        _error = null;
      });
    } else {
      _error = null;
    }
    try {
      if (refreshUserListability) {
        RemoteNotificationUserListabilityCache.instance.clear();
        RemoteNotificationProductListabilityCache.instance.clear();
        RemoteNotificationReviewContextCache.instance.clear();
      }
      final pageSize = background
          ? (_items.isEmpty
              ? kStandardListPageSize
              : _items.length.clamp(kStandardListPageSize, 50))
          : kStandardListPageSize;
      final res = await _repository.getFriendsFeed(page: 0, size: pageSize);
      final mapped = activityItemsFromFriendsFeedDtos(res.content);
      if (!mounted) return;
      // Sunucu aynı URL ile yeni piksel döndürebilir; tüm profil byte önbelleğini boşalt.
      clearProfileImageByteCache();
      setState(() {
        _items
          ..clear()
          ..addAll(mapped);
        _page = res.number;
        _totalPages = res.totalPages;
        _loadingFirst = false;
      });
      FriendFeedMemoryCache.instance.remember(
        items: _items,
        page: _page,
        totalPages: _totalPages,
      );
      _prefetchItemVisuals(_items);
      await _syncFollowingForCurrentItems(refetchFollowingSet: true);
      _scheduleFriendFeedPrefetchIfNeeded();
    } catch (e) {
      if (background && _items.isNotEmpty) {
        // keep stale list
      } else {
        if (!mounted) return;
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      _loadFirstInFlight = false;
      if (!background && mounted) setState(() => _loadingFirst = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final res = await _repository.getFriendsFeed(
        page: _page + 1,
        size: kStandardListPageSize,
      );
      if (!mounted) return;
      final mapped = activityItemsFromFriendsFeedDtos(res.content);
      final knownAvatarByUserId = <String, String?>{};
      for (final i in _items) {
        final id = i.user.id.trim();
        if (id.isEmpty) continue;
        knownAvatarByUserId[id] = i.user.avatarUrl;
      }
      for (final i in mapped) {
        final id = i.user.id.trim();
        if (id.isEmpty) continue;
        final before = knownAvatarByUserId[id];
        final after = i.user.avatarUrl;
        if (before != after) {
          evictProfileImageBytesCacheForRaw(before);
          evictProfileImageBytesCacheForRaw(after);
        }
      }
      setState(() {
        _items.addAll(mapped);
        _page = res.number;
        _totalPages = res.totalPages;
      });
      FriendFeedMemoryCache.instance.remember(
        items: _items,
        page: _page,
        totalPages: _totalPages,
      );
      _prefetchItemVisuals(_items);
      await _syncFollowingForCurrentItems(refetchFollowingSet: true);
      _scheduleFriendFeedPrefetchIfNeeded();
    } catch (_) {
      // best effort pagination
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  BottomNavigationBar _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 1,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      selectedFontSize: 0,
      unselectedFontSize: 0,
      onTap: (index) {
        if (index == 1) return;
        if (index == 0) {
          Navigator.pushReplacement(context, _instantRoute(const SearchPage()));
          return;
        }
        if (index == 2) {
          Navigator.pushReplacement(context, _instantRoute(const HomePage()));
          return;
        }
        if (index == 3) {
          Navigator.pushReplacement(context, _instantRoute(const ActivityPage()));
          return;
        }
        if (index == 4) {
          Navigator.pushReplacement(context, _instantRoute(const ProfilePage()));
        }
      },
      items: MainBottomNavItems.barItems,
    );
  }

  Future<void> _toggleFollow(String userId) async {
    if (userId.isEmpty) return;
    if (!_friendFeedFollowLock.tryEnter(userId)) return;
    final token = await _sessionHelper.ensureSession();
    if (token == null) {
      _friendFeedFollowLock.leave(userId);
      return;
    }
    try {
      final following = await _interactions.toggleFollow(token, userId);
      if (!mounted) return;
      setState(() {
        if (following) {
          _followingIds.add(userId);
        } else {
          _followingIds.remove(userId);
        }
      });
    } catch (_) {
      // best effort; ignore race/dup tap errors
    } finally {
      _friendFeedFollowLock.leave(userId);
    }
  }

  Future<void> _openItem(ActivityItem item) async {
    final pid = item.targetContent?.productId;
    if (pid == null || pid.isEmpty) return;

    // Use cached product if available; otherwise build a pre-filled placeholder
    // so ReviewPage shows the thumbnail immediately instead of a blank skeleton.
    final cached = ProductMemoryCache.instance.peek(pid);
    final placeholder = cached ??
        ProductDto(
          id: pid,
          name: item.targetContent?.title ?? '',
          imageURL: item.targetContent?.thumbnailUrl ?? '',
          tag: TagDto(id: '', name: ''),
        );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewPage(product: placeholder),
      ),
    );
  }

  List<ActivityItem> get _reviews =>
      _items.where((e) => e.type == ActivityType.review).toList();
  List<ActivityItem> get _likes =>
      _items.where((e) => e.type == ActivityType.like).toList();

  List<ActivityItem> _tabSource(int tab) {
    switch (tab) {
      case 1:
        return _reviews;
      case 2:
        return _likes;
      default:
        return _items;
    }
  }

  void _maybeLoadMoreFriendFeed(int tab, ScrollMetrics metrics) {
    if (tab != _tabController.index) return;
    if (!metrics.hasPixels) return;
    if (_loadingMore || _loadFirstInFlight) return;
    if (_error != null) return;
    if (_page + 1 >= _totalPages) return;
    if (metrics.maxScrollExtent <= 0) return;
    if (metrics.pixels < metrics.maxScrollExtent - 360) return;
    unawaited(_loadMore());
  }

  void _scheduleFriendFeedPrefetchIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_loadingMore || _loadFirstInFlight) return;
      if (_page + 1 >= _totalPages) return;
      final tab = _tabController.index;
      final c = _tabScrollControllers[tab];
      if (!c.hasClients) return;
      if (c.position.maxScrollExtent > 72) return;
      unawaited(_loadMore());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.background.withValues(alpha: 0.96),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: AppColors.primary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          toolbarHeight: AppSpacing.toolbarHeight,
          centerTitle: true,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFB5003A),
                  AppColors.primary,
                  Color(0xFF6B001F),
                ],
              ),
            ),
          ),
          title: const Text(
            'Friends Feed',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              color: AppColors.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FeedScreenTabBar(
                    controller: _tabController,
                    tabLabels: const ['All', 'Reviews', 'Likes'],
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
        ),
        body: _loadingFirst
            ? const ActivityFeedListSkeleton()
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xLarge),
                      child: Text(_error!, style: AppTextStyles.body, textAlign: TextAlign.center),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(0),
                      _buildList(1),
                      _buildList(2),
                    ],
                  ),
        bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildList(int tabIndex) {
    final list = _tabSource(tabIndex);
    if (list.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _loadFirst(
              background: _items.isNotEmpty,
              refreshUserListability: true,
            ),
        child: ListView(
          controller: _tabScrollControllers[tabIndex],
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No friend activity yet')),
          ],
        ),
      );
    }
    final tail = _loadingMore && _page + 1 < _totalPages ? 1 : 0;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _loadFirst(
        background: _items.isNotEmpty,
        refreshUserListability: true,
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          if (n.metrics.axis == Axis.vertical &&
              (n is ScrollUpdateNotification || n is ScrollEndNotification)) {
            _maybeLoadMoreFriendFeed(tabIndex, n.metrics);
          }
          return false;
        },
        child: ListView.builder(
          controller: _tabScrollControllers[tabIndex],
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          itemCount: list.length + tail,
          itemBuilder: (context, index) {
            if (index >= list.length) {
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
            final item = list[index];
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
                  following: _followingIds.contains(item.user.id),
                  onToggleFollow: () => _toggleFollow(item.user.id),
                  onOpen: () => _openItem(item),
                  onUserTap: () {
                    if (item.user.id.isEmpty) return;
                    openUserProfileIfActive(
                      context,
                      userId: item.user.id,
                      userName: item.user.username,
                      profileImageUrl: item.user.avatarUrl,
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

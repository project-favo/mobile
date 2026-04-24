import 'dart:async';
import 'dart:math' as math;

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
import '../../../core/widgets/paged_navigation_bar.dart';
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
  final List<int> _pageInTab = [0, 0, 0];
  final List<bool> _tabPrefetchFailed = [false, false, false];
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
        setState(() {
          _pageInTab[i] = 0;
          for (var k = 0; k < 3; k++) {
            _tabPrefetchFailed[k] = false;
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_tabScrollControllers[i].hasClients) {
            _tabScrollControllers[i].jumpTo(0);
          }
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

  void _scrollTabToTop(int tab) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tabScrollControllers[tab].hasClients) {
        _tabScrollControllers[tab].jumpTo(0);
      }
    });
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
      setState(() {
        _items
          ..clear()
          ..addAll(mapped);
        _page = res.number;
        _totalPages = res.totalPages;
        _loadingFirst = false;
        for (var k = 0; k < 3; k++) {
          _tabPrefetchFailed[k] = false;
        }
      });
      FriendFeedMemoryCache.instance.remember(
        items: _items,
        page: _page,
        totalPages: _totalPages,
      );
      _prefetchItemVisuals(_items);
      await _syncFollowingForCurrentItems(refetchFollowingSet: true);
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
      setState(() {
        final mapped = activityItemsFromFriendsFeedDtos(res.content);
        _items.addAll(mapped);
        _page = res.number;
        _totalPages = res.totalPages;
        for (var k = 0; k < 3; k++) {
          _tabPrefetchFailed[k] = false;
        }
      });
      FriendFeedMemoryCache.instance.remember(
        items: _items,
        page: _page,
        totalPages: _totalPages,
      );
      _prefetchItemVisuals(_items);
      await _syncFollowingForCurrentItems(refetchFollowingSet: true);
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
      FollowingIdSetCache.instance.applyToggle(userId, following);
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

  int _displayPage1Based(int tab) {
    final s = _tabSource(tab);
    if (s.isEmpty) return 1;
    var p = _pageInTab[tab];
    final maxP = math.max(0, ((s.length - 1) ~/ kStandardListPageSize));
    if (p > maxP) p = maxP;
    return p + 1;
  }

  int _totalTabPages(int tab) {
    final n = _tabSource(tab).length;
    if (n == 0) return 1;
    return ((n - 1) ~/ kStandardListPageSize) + 1;
  }

  bool _canGoPrevFd(int tab) => _pageInTab[tab] > 0;

  bool _canGoNextFd(int tab) {
    final s = _tabSource(tab);
    if (s.isEmpty) return false;
    if (_tabPrefetchFailed[tab]) return false;
    final p = _pageInTab[tab];
    if ((p + 1) * kStandardListPageSize < s.length) return true;
    return _page + 1 < _totalPages;
  }

  List<ActivityItem> _slicedForTab(int tab) {
    final s = _tabSource(tab);
    if (s.isEmpty) return const [];
    var p = _pageInTab[tab];
    final maxP = math.max(0, ((s.length - 1) ~/ kStandardListPageSize));
    if (p > maxP) p = maxP;
    final start = p * kStandardListPageSize;
    if (start >= s.length) return const [];
    final end = math.min(start + kStandardListPageSize, s.length);
    return s.sublist(start, end);
  }

  Future<void> _goNextFd(int tab) async {
    if (!_canGoNextFd(tab)) return;
    var p = _pageInTab[tab];
    var s = _tabSource(tab);
    if ((p + 1) * kStandardListPageSize < s.length) {
      setState(() => _pageInTab[tab] = p + 1);
      _scrollTabToTop(tab);
      return;
    }
    if (_page + 1 >= _totalPages) return;
    var guard = 40;
    while (_page + 1 < _totalPages && guard-- > 0) {
      final before = _items.length;
      await _loadMore();
      if (!mounted) return;
      s = _tabSource(tab);
      if ((p + 1) * kStandardListPageSize < s.length) {
        setState(() {
          _pageInTab[tab] = p + 1;
          _tabPrefetchFailed[tab] = false;
        });
        _scrollTabToTop(tab);
        return;
      }
      if (_items.length == before) break;
    }
    if (!mounted) return;
    if ((p + 1) * kStandardListPageSize >= _tabSource(tab).length) {
      setState(() => _tabPrefetchFailed[tab] = true);
    }
  }

  void _goPrevFd(int tab) {
    if (_pageInTab[tab] <= 0) return;
    setState(() {
      _pageInTab[tab]--;
      _tabPrefetchFailed[tab] = false;
    });
    _scrollTabToTop(tab);
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
            'Friends Feed',
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
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'All'),
                      Tab(text: 'Reviews'),
                      Tab(text: 'Likes'),
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
    final slice = _slicedForTab(tabIndex);
    final p = _pageInTab[tabIndex];
    final rangeStart = p * kStandardListPageSize + 1;
    final rangeEnd = math.min(
      (p + 1) * kStandardListPageSize,
      list.length,
    );
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => _loadFirst(
              background: _items.isNotEmpty,
              refreshUserListability: true,
            ),
            child: ListView.separated(
              controller: _tabScrollControllers[tabIndex],
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              itemCount: slice.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = slice[index];
                return Container(
                  key: ValueKey(item.id),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.7),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
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
                );
              },
            ),
          ),
        ),
        PagedNavigationBar(
          currentPage1Based: _displayPage1Based(tabIndex),
          totalPages: _totalTabPages(tabIndex),
          canGoPrevious: _canGoPrevFd(tabIndex),
          canGoNext: _canGoNextFd(tabIndex),
          isLoadingNext: _loadingMore,
          onPrevious: () => _goPrevFd(tabIndex),
          onNext: () {
            unawaited(_goNextFd(tabIndex));
          },
          showTopDivider: true,
          rangeStart1Based: rangeStart,
          rangeEnd1Based: rangeEnd,
          rangeTotal: list.length,
          itemNounPlural: 'activities',
        ),
      ],
    );
  }
}

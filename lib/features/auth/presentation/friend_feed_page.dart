import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/cache/following_id_set_cache.dart';
import '../../../core/cache/friend_feed_memory_cache.dart';
import 'profile/pages/user_profile_page.dart';
import '../../../core/cache/product_memory_cache.dart';
import '../data/models/product_dto.dart';
import '../data/models/tag_dto.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/load_profile_image_bytes.dart';
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

class _FriendFeedPageState extends State<FriendFeedPage> {
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
  Timer? _feedPollTimer;
  bool _loadFirstInFlight = false;
  static const _feedPollInterval = Duration(seconds: 5);

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
      unawaited(_syncFollowingForCurrentItems());
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
    _feedPollTimer = Timer.periodic(_feedPollInterval, (_) {
      unawaited(_loadFirst(background: true));
    });
  }

  @override
  void dispose() {
    _feedPollTimer?.cancel();
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

  Future<void> _syncFollowingForCurrentItems() async {
    final token = await _sessionHelper.ensureSession();
    if (token == null) return;
    final ids = _items.map((e) => e.user.id).where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    try {
      await FollowingIdSetCache.instance.ensureLoaded(
        _interactions,
        AuthService(),
        _sessionHelper,
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

  Future<void> _loadFirst({bool background = false}) async {
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
      final pageSize = background
          ? (_items.isEmpty
              ? 20
              : _items.length.clamp(20, 50))
          : 20;
      final res = await _repository.getFriendsFeed(page: 0, size: pageSize);
      final mapped = res.content.map(activityItemFromFriendsFeed).toList();
      if (!mounted) return;
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
      await _syncFollowingForCurrentItems();
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
      final res = await _repository.getFriendsFeed(page: _page + 1, size: 20);
      if (!mounted) return;
      setState(() {
        final mapped = res.content.map(activityItemFromFriendsFeed).toList();
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
      await _syncFollowingForCurrentItems();
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
                    children: [
                      _buildList(_items),
                      _buildList(_reviews),
                      _buildList(_likes),
                    ],
                  ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildList(List<ActivityItem> list) {
    if (list.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _loadFirst(background: _items.isNotEmpty),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No friend activity yet')),
          ],
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 200) {
          if (!_loadingMore && !_loadingFirst && _page + 1 < _totalPages) {
            unawaited(_loadMore());
          }
        }
        return false;
      },
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _loadFirst(background: _items.isNotEmpty),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          itemCount: list.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index >= list.length) {
              return const ActivityFeedLoadMoreSkeleton();
            }
            final item = list[index];
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
                following: _followingIds.contains(item.user.id),
                onToggleFollow: () => _toggleFollow(item.user.id),
                onOpen: () => _openItem(item),
                onUserTap: () {
                  if (item.user.id.isEmpty) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UserProfilePage(
                        userId: item.user.id,
                        userName: item.user.username,
                        profileImageUrl: item.user.avatarUrl,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

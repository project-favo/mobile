import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/notifications/notification_realtime_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../data/models/notification_dto.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/utils/notification_remote_user_filter.dart';
import '../../../data/models/notification_section.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../review/pages/review_page.dart';

/// Tarihler ve metinler İngilizce (ekran dili ne olursa olsun).
const String _kDateLocale = 'en_US';

String _notificationActorInitial(NotificationDto n) {
  final u = n.actor?.userName?.trim();
  if (u != null && u.isNotEmpty) return u;
  final d = n.actorDisplayName?.trim();
  if (d != null && d.isNotEmpty) return d;
  return '?';
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final NotificationRepository _repository = NotificationRepository();
  final AuthService _auth = AuthService();
  final ScrollController _scrollController = ScrollController();

  final List<NotificationDto> _items = [];
  StreamSubscription<NotificationPushEvent>? _pushSub;

  late final Map<NotificationSection, bool> _sectionExpanded;

  bool _loadingFirst = true;
  bool _loadingMore = false;
  String? _errorMessage;
  int _page = 0;
  int _totalPages = 1;
  bool _markingAll = false;
  Timer? _pollTimer;
  bool _backgroundSyncInFlight = false;
  static const _pollInterval = Duration(seconds: 5);
  static const int _maxPollListSize = 100;

  @override
  void initState() {
    super.initState();
    _sectionExpanded = {
      for (final s in NotificationSection.values) s: true,
    };
    NotificationRealtimeService.instance.attach();
    _pushSub = NotificationRealtimeService.instance.pushStream.listen((e) {
      unawaited(_onRealtimePush(e));
    });
    _scrollController.addListener(_onScroll);
    unawaited(_loadFirstPage());
    unawaited(NotificationRealtimeService.instance.refreshUnread());
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_syncNotificationsInBackground());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pushSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    NotificationRealtimeService.instance.detach();
    super.dispose();
  }

  Future<void> _onRealtimePush(NotificationPushEvent e) async {
    final n = e.notification;
    if (n == null || !mounted) return;
    final visible = await filterNotificationsHidingUnlistedUsers([n], _auth);
    if (visible.isEmpty || !mounted) return;
    final n2 = visible.first;
    if (_items.any((x) => x.id == n2.id)) return;
    setState(() {
      _items.insert(0, n2);
    });
  }

  void _onScroll() {
    if (_loadingMore || _loadingFirst) return;
    if (_page + 1 >= _totalPages) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loadingFirst = true;
      _errorMessage = null;
      _page = 0;
    });
    try {
      final page = await _repository.getNotifications(page: 0, size: 20);
      if (!mounted) return;
      final list = await filterNotificationsHidingUnlistedUsers(
        page.content,
        _auth,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _page = page.number;
        _totalPages = page.totalPages;
        _loadingFirst = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _loadingFirst = false;
      });
    }
  }

  /// Periyodik: sunucu deaktif ürün / silinen kullanıcı satırlarını kaldırdıysa listeyi hizala.
  Future<void> _syncNotificationsInBackground() async {
    if (!mounted || _backgroundSyncInFlight || _loadingFirst) return;
    _backgroundSyncInFlight = true;
    try {
      final want = _items.isEmpty
          ? 20
          : _items.length.clamp(20, _maxPollListSize);
      final page = await _repository.getNotifications(page: 0, size: want);
      if (!mounted) return;
      final list = await filterNotificationsHidingUnlistedUsers(
        page.content,
        _auth,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _page = page.number;
        _totalPages = page.totalPages;
      });
      await NotificationRealtimeService.instance.refreshUnread();
    } catch (_) {
      // Sessiz; açık listeyi koru.
    } finally {
      _backgroundSyncInFlight = false;
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page + 1 >= _totalPages) return;
    setState(() => _loadingMore = true);
    try {
      final next =
          await _repository.getNotifications(page: _page + 1, size: 20);
      if (!mounted) return;
      final more = await filterNotificationsHidingUnlistedUsers(
        next.content,
        _auth,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(more);
        _page = next.number;
        _totalPages = next.totalPages;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await _repository.markAllRead();
      if (!mounted) return;
      await _loadFirstPage();
      await NotificationRealtimeService.instance.refreshUnread();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getUserFriendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _onTapItem(NotificationDto n) async {
    if (n.isUnread) {
      try {
        await _repository.markRead(n.id);
        if (!mounted) return;
        final idx = _items.indexWhere((e) => e.id == n.id);
        if (idx != -1) {
          setState(() {
            _items[idx] = n.copyWith(readAt: DateTime.now());
          });
        }
        await NotificationRealtimeService.instance.refreshUnread();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserFriendlyMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    if (!mounted) return;
    _tryNavigateFromPayload(n);
  }

  void _tryNavigateFromPayload(NotificationDto n) {
    final raw = n.payloadJson?.trim();
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final productId = map['productId']?.toString();
      if (productId == null || productId.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewPage(
            productId: productId,
            productName: map['productName']?.toString() ?? n.title,
          ),
        ),
      );
    } catch (_) {}
  }

  String _formatTimestamp(DateTime? d) {
    if (d == null) return '';
    final local = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final time = DateFormat.Hm(_kDateLocale).format(local);

    if (day == today) {
      return 'Today · $time';
    }
    if (day == yesterday) {
      return 'Yesterday · $time';
    }
    if (local.year == now.year) {
      return '${DateFormat.MMMd(_kDateLocale).format(local)} · $time';
    }
    return '${DateFormat.yMMMd(_kDateLocale).format(local)} · $time';
  }

  Future<bool> _confirmDelete(NotificationDto n) async {
    final del = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete notification'),
        content: const Text(
          'Remove this notification permanently?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return del == true;
  }

  Future<bool> _deleteNotification(NotificationDto n) async {
    final ok = await _confirmDelete(n);
    if (!ok || !mounted) return false;
    try {
      await _repository.deleteNotification(n.id);
      if (!mounted) return false;
      await NotificationRealtimeService.instance.refreshUnread();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserFriendlyMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    }
  }

  Future<bool?> _onDismissConfirm(NotificationDto n) async {
    return _deleteNotification(n);
  }

  void _onDismissed(NotificationDto n) {
    setState(() {
      _items.removeWhere((e) => e.id == n.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        toolbarHeight: AppSpacing.toolbarHeight,
        title: const Text('Notifications', style: AppTextStyles.HomeHeader),
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
          child: BackButton(
            color: AppColors.primary,
            onPressed: () => Navigator.pop(context, true),
          ),
        ),
        actions: [
          if (!_loadingFirst && _items.isNotEmpty)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: Text(
                'Read all',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppColors.textSecondary.withValues(alpha: 0.2),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await _loadFirstPage();
          await NotificationRealtimeService.instance.refreshUnread();
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingFirst) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: AppSpacing.large),
        children: [
          for (var i = 0; i < 8; i++) const NotificationTileSkeleton(),
        ],
      );
    }
    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.xLarge),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline, size: 56, color: AppColors.error),
          const SizedBox(height: AppSpacing.large),
          Text(
            _errorMessage!,
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.large),
          Center(
            child: TextButton(
              onPressed: _loadFirstPage,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
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
            'No notifications yet',
            style: AppTextStyles.bodySecondary,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final grouped = groupNotifications(_items);
    final orderedSections = List<NotificationSection>.from(
      NotificationSection.values,
    )..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    final sectionWidgets = <Widget>[];
    for (final section in orderedSections) {
      final list = grouped[section]!;
      if (list.isEmpty) continue;

      final countLabel =
          list.length == 1 ? '1 notification' : '${list.length} notifications';

      sectionWidgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.medium,
            AppSpacing.small,
            AppSpacing.medium,
            AppSpacing.small,
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Material(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              child: ExpansionTile(
                key: PageStorageKey<String>('notif-section-${section.name}'),
                initiallyExpanded: _sectionExpanded[section] ?? true,
                onExpansionChanged: (open) {
                  setState(() => _sectionExpanded[section] = open);
                },
                leading: Icon(section.icon, color: AppColors.primary, size: 22),
                title: Text(
                  section.title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  countLabel,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: AppColors.surface,
                collapsedBackgroundColor: AppColors.surface,
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.medium),
                children: [
                  for (final n in list)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.small,
                        0,
                        AppSpacing.small,
                        AppSpacing.medium,
                      ),
                      child: Dismissible(
                        key: ValueKey('notification-${n.id}'),
                        direction: DismissDirection.endToStart,
                        background: const _DismissDeleteBackground(),
                        confirmDismiss: (_) => _onDismissConfirm(n),
                        onDismissed: (_) => _onDismissed(n),
                        child: _NotificationTile(
                          notification: n,
                          timestamp: _formatTimestamp(n.createdAt),
                          onTap: () => _onTapItem(n),
                          onDelete: () async {
                            if (await _deleteNotification(n) && mounted) {
                              setState(() {
                                _items.removeWhere((e) => e.id == n.id);
                              });
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_loadingMore) {
      sectionWidgets.add(
        const Padding(
          padding: EdgeInsets.all(AppSpacing.large),
          child: Center(child: ListLoadMoreSkeleton()),
        ),
      );
    }

    sectionWidgets.add(const SizedBox(height: AppSpacing.large));

    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: AppSpacing.small),
      children: sectionWidgets,
    );
  }
}

class _DismissDeleteBackground extends StatelessWidget {
  const _DismissDeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.xLarge),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 6),
          Text(
            'Delete',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationDto notification;
  final String timestamp;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.notification,
    required this.timestamp,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return Material(
      color: n.isUnread
          ? AppColors.primary.withValues(alpha: 0.06)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.large,
            AppSpacing.medium,
            AppSpacing.small,
            AppSpacing.medium,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (n.actor != null) ...[
                ProfileAvatar(
                  radius: 22,
                  imageUrl: n.actor!.profileImageUrl.trim().isEmpty
                      ? null
                      : n.actor!.profileImageUrl,
                  fallbackInitial: _notificationActorInitial(n),
                ),
                const SizedBox(width: AppSpacing.medium),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: n.isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (n.isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8, top: 6),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (n.actorDisplayName != null &&
                        n.actorDisplayName!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.small),
                      Text(
                        n.actorDisplayName!,
                        style: AppTextStyles.bodySecondary.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (n.body != null && n.body!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.small),
                      Text(
                        n.body!,
                        style: AppTextStyles.bodySecondary,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.small),
                    Text(
                      timestamp,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.textSecondary.withValues(alpha: 0.85),
                ),
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline,
                            color: AppColors.error, size: 20),
                        const SizedBox(width: AppSpacing.small),
                        Text(
                          'Delete',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

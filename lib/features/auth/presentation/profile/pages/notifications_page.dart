import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../../core/notifications/notification_realtime_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../data/models/notification_dto.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../review/pages/review_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final NotificationRepository _repository = NotificationRepository();
  final ScrollController _scrollController = ScrollController();

  final List<NotificationDto> _items = [];
  StreamSubscription<NotificationPushEvent>? _pushSub;

  bool _loadingFirst = true;
  bool _loadingMore = false;
  String? _errorMessage;
  int _page = 0;
  int _totalPages = 1;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    NotificationRealtimeService.instance.attach();
    _pushSub =
        NotificationRealtimeService.instance.pushStream.listen(_onRealtimePush);
    _scrollController.addListener(_onScroll);
    unawaited(_loadFirstPage());
    unawaited(NotificationRealtimeService.instance.refreshUnread());
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    NotificationRealtimeService.instance.detach();
    super.dispose();
  }

  void _onRealtimePush(NotificationPushEvent e) {
    final n = e.notification;
    if (n == null || !mounted) return;
    if (_items.any((x) => x.id == n.id)) return;
    setState(() {
      _items.insert(0, n);
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
      setState(() {
        _items
          ..clear()
          ..addAll(page.content);
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

  Future<void> _loadMore() async {
    if (_loadingMore || _page + 1 >= _totalPages) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _repository.getNotifications(page: _page + 1, size: 20);
      if (!mounted) return;
      setState(() {
        _items.addAll(next.content);
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

  String _formatTime(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
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
        children: [
          const SizedBox(height: 120),
          const Center(child: CircularProgressIndicator()),
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

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.medium,
      ),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.large),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final n = _items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.medium),
          child: Material(
            color: n.isUnread
                ? AppColors.primary.withValues(alpha: 0.06)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _onTapItem(n),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.large),
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
                              fontWeight:
                                  n.isUnread ? FontWeight.w700 : FontWeight.w600,
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
                          fontWeight: FontWeight.w500,
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
                      _formatTime(n.createdAt),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

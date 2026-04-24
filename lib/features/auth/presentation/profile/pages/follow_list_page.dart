import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/config/app_background_timers.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/utils/user_profile_navigation.dart';
import '../../../data/models/conversation_dto.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/services/auth_service.dart';
class FollowListPage extends StatefulWidget {
  final String userId;
  final String title;
  final bool isFollowers;

  const FollowListPage({
    super.key,
    required this.userId,
    required this.title,
    required this.isFollowers,
  });

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> {
  final InteractionRepository _repo = InteractionRepository();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollTimer;

  List<ConversationUserDto> _users = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 0;
  bool _hasMore = true;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _resolveMyUserId();
    _loadPage();
    _scrollController.addListener(_onScroll);
    _pollTimer = Timer.periodic(
      AppBackgroundTimers.standardListPoll,
      (_) => unawaited(_resyncListSilently()),
    );
  }

  /// Poll: iskelet yok, pasif/takip düşer.
  Future<void> _resyncListSilently() async {
    if (!mounted) return;
    if (_isLoading) return;
    final result = await _fetch(0);
    if (!mounted) return;
    setState(() {
      _users = result;
      if (result.length < 20) {
        _hasMore = false;
        _page = 0;
      }
    });
  }

  Future<void> _resolveMyUserId() async {
    try {
      final me = await AuthService().getMe();
      if (!mounted) return;
      setState(() => _myUserId = me.id);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadPage() async {
    setState(() {
      _isLoading = true;
      _page = 0;
      _hasMore = true;
    });
    final result = await _fetch(0);
    if (!mounted) return;
    setState(() {
      _users = result;
      _isLoading = false;
      if (result.length < 20) _hasMore = false;
    });
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    final next = _page + 1;
    final result = await _fetch(next);
    if (!mounted) return;
    setState(() {
      _page = next;
      _users.addAll(result);
      _isLoadingMore = false;
      if (result.length < 20) _hasMore = false;
    });
  }

  Future<List<ConversationUserDto>> _fetch(int page) async {
    if (widget.isFollowers) {
      return _repo.getFollowers(widget.userId, page: page);
    } else {
      return _repo.getFollowing(widget.userId, page: page);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Text(
          widget.title,
          style: AppTextStyles.heading3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xLarge,
                vertical: AppSpacing.large,
              ),
              children: [
                for (var i = 0; i < 10; i++) const FollowUserRowSkeleton(),
              ],
            )
          : _users.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xLarge),
                    child: Text(
                      widget.isFollowers
                          ? 'No followers yet.'
                          : 'Not following anyone yet.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _loadPage,
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xLarge,
                      vertical: AppSpacing.large,
                    ),
                    itemCount: _users.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _users.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.large),
                          child: Center(child: ListLoadMoreSkeleton()),
                        );
                      }
                      final user = _users[index];
                      return _UserListTile(
                        user: user,
                        onTap: () {
                          final my = _myUserId;
                          if (my != null &&
                              my.trim() == user.id.toString().trim()) {
                            return;
                          }
                          openUserProfileIfActive(
                            context,
                            userId: user.id.toString(),
                            userName: user.username,
                            profileImageUrl: user.profilePhotoUrl,
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class _UserListTile extends StatelessWidget {
  final ConversationUserDto user;
  final VoidCallback onTap;

  const _UserListTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = user.profilePhotoUrl;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.medium,
        vertical: AppSpacing.small,
      ),
      leading: ProfileAvatar(
        radius: 22,
        imageUrl: url,
        fallbackInitial: user.username,
      ),
      title: Text(
        user.username,
        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}

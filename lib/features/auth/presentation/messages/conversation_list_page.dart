import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/config/app_background_timers.dart';
import '../../../../core/utils/entity_active.dart';
import '../../../../core/utils/app_datetime.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/session_helper.dart';
import '../../../../core/utils/resolve_media_url.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../../../core/utils/load_profile_image_bytes.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/models/conversation_dto.dart';
import '../../data/services/auth_service.dart';
import '../../../../core/notifications/message_unread_service.dart';
import '../../../../core/cache/conversation_list_cache.dart';
import '../../../../core/routes/custom_page_transitions.dart';
import 'chat_detail_page.dart';

class ConversationListPage extends StatefulWidget {
  const ConversationListPage({super.key});

  @override
  State<ConversationListPage> createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage> {
  final SessionHelper _sessionHelper = SessionHelper();
  final MessageRepository _messageRepository = MessageRepository();
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  String? _errorMessage;
  List<ConversationDto> _conversations = [];
  /// Konuşma API’si avatar göndermiyorsa [getUserById] ile doldurulur.
  final Map<int, ({String? url, Uint8List? bytes})> _avatarExtras = {};

  Timer? _pollTimer;
  final Set<int> _openingConversationIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadConversations();
    MessageUnreadService.instance.attach();
    // Pasif/deaktif konuşmaları düşür + yeni mesaj
    _pollTimer = Timer.periodic(AppBackgroundTimers.standardListPoll, (_) {
      unawaited(_silentRefresh());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    MessageUnreadService.instance.detach();
    super.dispose();
  }

  Future<void> _silentRefresh() async {
    try {
      final page = await _messageRepository.getConversations(page: 0, size: 20);
      if (!mounted) return;
      final sorted = _filterAndSort(page.content);
      final changed = _conversationsMeaningfullyChanged(sorted, _conversations);
      // Unread badge'ini her zaman güncelle
      final unread = sorted.where((c) => c.unreadCount > 0).length;
      MessageUnreadService.instance.unreadCount.value = unread;

      if (changed && mounted) {
        _evictAvatarCachesIfParticipantVisualChanged(sorted, _conversations);
        ConversationListCache.instance.remember(sorted);
        _dropExtrasShadowedByDto(sorted);
        setState(() => _conversations = sorted);
        _enrichConversationAvatars(sorted);
        _warmAvatarCacheForConversations(sorted);
      }
    } catch (_) {
      // Arka plan poll hatasını sustur
    }
  }

  Future<void> _loadConversations() async {
    await ConversationListCache.instance.restoreFromDisk();
    // Cache varsa anında göster
    final warm = ConversationListCache.instance.peek();
    if (warm != null && warm.isNotEmpty) {
      final visible = filterVisibleConversations(warm);
      setState(() {
        _conversations = visible;
        _isLoading = false;
      });
      unawaited(_enrichConversationAvatars(visible));
      _warmAvatarCacheForConversations(visible);
      unawaited(_refreshConversationsInBackground());
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Please login to see your messages.');
      }
      final page = await _messageRepository.getConversations(page: 0, size: 20);
      if (!mounted) return;
      final sorted = _filterAndSort(page.content);
      ConversationListCache.instance.remember(sorted);
      setState(() {
        _conversations = sorted;
        _isLoading = false;
      });
      _enrichConversationAvatars(sorted);
      _warmAvatarCacheForConversations(sorted);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
    }
  }

  List<ConversationDto> _sortedConversations(List<ConversationDto> list) {
    return [...list]..sort((a, b) {
        final da = parseBackendDateTimeToLocal(a.lastMessageAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final db = parseBackendDateTimeToLocal(b.lastMessageAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
  }

  List<ConversationDto> _filterAndSort(List<ConversationDto> raw) {
    return _sortedConversations(filterVisibleConversations(raw));
  }

  Future<void> _refreshConversationsInBackground() async {
    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) return;
      final page = await _messageRepository.getConversations(page: 0, size: 20);
      if (!mounted) return;
      final sorted = _filterAndSort(page.content);
      final changed = _conversationsMeaningfullyChanged(sorted, _conversations);
      ConversationListCache.instance.remember(sorted);
      if (changed && mounted) {
        _evictAvatarCachesIfParticipantVisualChanged(sorted, _conversations);
        _dropExtrasShadowedByDto(sorted);
        setState(() => _conversations = sorted);
        _enrichConversationAvatars(sorted);
        _warmAvatarCacheForConversations(sorted);
      }
    } catch (_) {}
  }

  /// Sıra değişse bile aynı konuşma satırını `id` ile eşleyerek karşılaştırır (avatar güncellemesi kaçmasın).
  bool _conversationsMeaningfullyChanged(
    List<ConversationDto> next,
    List<ConversationDto> prev,
  ) {
    if (next.length != prev.length) return true;
    final prevById = {for (final c in prev) c.id: c};
    for (final n in next) {
      final o = prevById[n.id];
      if (o == null) return true;
      if (o.lastMessage != n.lastMessage || o.unreadCount != n.unreadCount) {
        return true;
      }
      final a = o.otherParticipant;
      final b = n.otherParticipant;
      if (a.profilePhotoUrl != b.profilePhotoUrl ||
          a.profilePhotoData != b.profilePhotoData) {
        return true;
      }
    }
    return false;
  }

  void _evictAvatarCachesIfParticipantVisualChanged(
    List<ConversationDto> next,
    List<ConversationDto> prev,
  ) {
    final prevById = {for (final c in prev) c.id: c};
    for (final n in next) {
      final o = prevById[n.id];
      if (o == null) continue;
      final a = o.otherParticipant;
      final b = n.otherParticipant;
      if (a.profilePhotoUrl != b.profilePhotoUrl ||
          a.profilePhotoData != b.profilePhotoData) {
        evictProfileImageBytesCacheForRaw(a.profilePhotoUrl);
        evictProfileImageBytesCacheForRaw(b.profilePhotoUrl);
      }
    }
  }

  /// API artık URL / inline veri gönderiyorsa eski [getUserById] eklerinin üstüne binmesin.
  void _dropExtrasShadowedByDto(List<ConversationDto> list) {
    for (final c in list) {
      final op = c.otherParticipant;
      final u = op.profilePhotoUrl?.trim();
      if (u != null && u.isNotEmpty) {
        _avatarExtras.remove(op.id);
        continue;
      }
      final bytes = decodeProfilePhotoBytes(op.profilePhotoData);
      if (bytes != null && bytes.isNotEmpty) {
        _avatarExtras.remove(op.id);
      }
    }
  }

  /// Konuşma DTO’sundaki avatar her zaman öncelikli; ekstra sadece API boşken kullanılır.
  ({String? url, Uint8List? bytes}) _effectiveAvatarFor(ConversationUserDto op) {
    final extra = _avatarExtras[op.id];
    final dtoUrl = op.profilePhotoUrl?.trim();
    final dtoBytes = decodeProfilePhotoBytes(op.profilePhotoData);
    if (dtoUrl != null && dtoUrl.isNotEmpty) {
      return (
        url: dtoUrl,
        bytes: dtoBytes != null && dtoBytes.isNotEmpty ? dtoBytes : null,
      );
    }
    if (dtoBytes != null && dtoBytes.isNotEmpty) {
      return (url: null, bytes: dtoBytes);
    }
    return (url: extra?.url, bytes: extra?.bytes);
  }

  void _warmAvatarCacheForConversations(List<ConversationDto> list) {
    for (final c in list) {
      final raw = c.otherParticipant.profilePhotoUrl;
      if (raw != null && raw.trim().isNotEmpty) {
        unawaited(loadProfileImageBytesFromRaw(raw));
      }
    }
  }

  bool _participantHasLoadableAvatar(ConversationUserDto op) {
    final url = op.profilePhotoUrl?.trim();
    if (url != null && url.isNotEmpty) return true;
    final bytes = decodeProfilePhotoBytes(op.profilePhotoData);
    return bytes != null && bytes.isNotEmpty;
  }

  Future<void> _enrichConversationAvatars(List<ConversationDto> list) async {
    final byId = <int, ConversationUserDto>{};
    for (final c in list) {
      final op = c.otherParticipant;
      if (op.id > 0) byId[op.id] = op;
    }
    final pending =
        byId.entries.where((e) {
          if (_participantHasLoadableAvatar(e.value)) return false;
          if (_avatarExtras.containsKey(e.key)) return false;
          return true;
        }).toList();

    final fetched = await Future.wait(
      pending.map((e) async {
        try {
          final idStr = e.key.toString();
          final pix = await _authService.fetchUserProfileImage(idStr);
          if (pix != null && (pix.isNotFound || pix.isActiveUserNoPhoto)) {
            return null;
          }
          if (pix != null && pix.hasImage) {
            return MapEntry(
              e.key,
              (url: pix.imageUrl, bytes: pix.memoryBytes),
            );
          }
          final u = await _authService.getUserById(idStr);
          if (u == null) return null;
          if (u.isProfileViewBlocked) return null;
          final bytes = decodeProfilePhotoBytes(u.profilePhotoData);
          final url = u.profileImageUrl?.trim();
          if ((url != null && url.isNotEmpty) ||
              (bytes != null && bytes.isNotEmpty)) {
            return MapEntry(e.key, (url: url, bytes: bytes));
          }
        } catch (_) {}
        return null;
      }),
    );

    final updates = <int, ({String? url, Uint8List? bytes})>{};
    for (final r in fetched) {
      if (r != null) updates[r.key] = r.value;
    }
    if (updates.isNotEmpty && mounted) {
      setState(() => _avatarExtras.addAll(updates));
      for (final e in updates.values) {
        final u = e.url;
        if (u != null && u.trim().isNotEmpty) {
          unawaited(loadProfileImageBytesFromRaw(u));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
        ),
        title: const Text(
          'Messages',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
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
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadConversations,
        child: _isLoading
            ? ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.xLarge),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, __) => const _ConversationRowSkeleton(),
              )
            : _errorMessage != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.4,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.error_outline_rounded,
                                size: 32,
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.large),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xLarge,
                              ),
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xLarge),
                            ElevatedButton(
                              onPressed: _loadConversations,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text(
                                'Try again',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : _conversations.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.42,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.08,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 34,
                                    color: AppColors.primary.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.large),
                                const Text(
                                  'No conversations yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.small),
                                const Text(
                                  'Start a conversation by visiting\nsomeone\'s profile.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    height: 1.4,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.xLarge),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        itemCount: _conversations.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final c = _conversations[index];
                          final av = _effectiveAvatarFor(c.otherParticipant);
                          final hasUnread = c.unreadCount > 0;
                          final timeParts =
                              conversationPreviewTimePartsFromBackend(
                            c.lastMessageAt,
                            fallback: '—',
                          );
                          return _ConversationListTile(
                            username: c.otherParticipant.username,
                            preview: c.lastMessage,
                            timeParts: timeParts,
                            hasUnread: hasUnread,
                            unreadCount: c.unreadCount,
                            avatar: ProfileAvatar(
                              radius: 22,
                              imageUrl: av.url,
                              memoryBytes: av.bytes,
                              fallbackInitial: c.otherParticipant.username,
                            ),
                            onTap: () async {
                              if (!isConversationDtoVisible(c)) {
                                unawaited(_loadConversations());
                                return;
                              }
                              if (_openingConversationIds.contains(c.id)) {
                                return;
                              }
                              _openingConversationIds.add(c.id);
                              if (!mounted) return;
                              try {
                                final result = await Navigator.push(
                                  context,
                                  SlideRightRoute(
                                    page: ChatDetailPage(conversation: c),
                                  ),
                                );
                                if (result == true && mounted) {
                                  await _loadConversations();
                                }
                              } finally {
                                _openingConversationIds.remove(c.id);
                              }
                            },
                          );
                        },
                      ),
      ),
    );
  }
}

class _ConversationListTile extends StatelessWidget {
  const _ConversationListTile({
    required this.username,
    required this.preview,
    required this.timeParts,
    required this.hasUnread,
    required this.unreadCount,
    required this.avatar,
    required this.onTap,
  });

  final String username;
  final String preview;
  final ConversationPreviewTimeParts timeParts;
  final bool hasUnread;
  final int unreadCount;
  final Widget avatar;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => unawaited(onTap()),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: AppColors.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
              if (hasUnread)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 2),
                ),
            ],
            border: Border.all(
              color: hasUnread
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : AppColors.border.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 15,
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.15,
                                height: 1.15,
                              ),
                            ),
                          ),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeParts.dateLine,
                      textAlign: TextAlign.end,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                        letterSpacing: 0.15,
                        height: 1.1,
                      ),
                    ),
                    if (timeParts.timeLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        timeParts.timeLine,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: hasUnread
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationRowSkeleton extends StatelessWidget {
  const _ConversationRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Row(
          children: [
            SkeletonLoader(
              width: 44,
              height: 44,
              borderRadius: BorderRadius.all(Radius.circular(22)),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader(width: 120, height: 14),
                  SizedBox(height: 6),
                  SkeletonLoader(width: 180, height: 12),
                ],
              ),
            ),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SkeletonLoader(width: 38, height: 10),
                SizedBox(height: 4),
                SkeletonLoader(width: 32, height: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

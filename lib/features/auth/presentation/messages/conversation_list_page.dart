import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/entity_active.dart';
import '../../../../core/utils/app_datetime.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/exceptions.dart';
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

  @override
  void initState() {
    super.initState();
    _loadConversations();
    MessageUnreadService.instance.attach();
    // 5 sn: pasif/deaktif konuşmaları düşür + yeni mesaj
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
      // Sadece gerçek değişiklik varsa rebuild et
      bool changed = sorted.length != _conversations.length;
      if (!changed) {
        for (int i = 0; i < sorted.length; i++) {
          final n = sorted[i];
          final o = _conversations[i];
          if (n.id != o.id ||
              n.lastMessage != o.lastMessage ||
              n.unreadCount != o.unreadCount) {
            changed = true;
            break;
          }
        }
      }
      // Unread badge'ini her zaman güncelle
      final unread = sorted.where((c) => c.unreadCount > 0).length;
      MessageUnreadService.instance.unreadCount.value = unread;

      if (changed && mounted) {
        ConversationListCache.instance.remember(sorted);
        setState(() => _conversations = sorted);
        _enrichConversationAvatars(sorted);
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
      setState(() {
        _conversations = filterVisibleConversations(warm);
        _isLoading = false;
      });
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
      ConversationListCache.instance.remember(sorted);
      bool changed = sorted.length != _conversations.length;
      if (!changed) {
        for (int i = 0; i < sorted.length; i++) {
          final n = sorted[i]; final o = _conversations[i];
          if (n.id != o.id || n.lastMessage != o.lastMessage || n.unreadCount != o.unreadCount) {
            changed = true; break;
          }
        }
      }
      if (changed && mounted) {
        setState(() => _conversations = sorted);
        _enrichConversationAvatars(sorted);
      }
    } catch (_) {}
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
          if (pix != null && pix.isNotFound) {
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

  String _formatTime(String iso) {
    return formatShortTimeFromBackend(iso, fallback: '');
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
          'Messages',
          style: AppTextStyles.heading3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/background.png', fit: BoxFit.cover),
          ),
          RefreshIndicator(
        onRefresh: _loadConversations,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: _isLoading
              ? ListView.separated(
                  itemCount: 6,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.medium),
                  itemBuilder: (context, index) => Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                      color: AppColors.surface,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: AppSpacing.medium,
                    ),
                    child: Row(
                      children: [
                        const SkeletonLoader(
                          width: 44,
                          height: 44,
                          borderRadius: BorderRadius.all(Radius.circular(22)),
                        ),
                        const SizedBox(width: AppSpacing.large),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              SkeletonLoader(width: 140, height: 16),
                              SizedBox(height: 6),
                              SkeletonLoader(width: 200, height: 14),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.large),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: const [
                            SkeletonLoader(width: 44, height: 14),
                            SizedBox(height: 6),
                            SkeletonLoader(
                              width: 20,
                              height: 20,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Text(
                        _errorMessage!,
                        style: AppTextStyles.bodySecondary.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _conversations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 48,
                                color: AppColors.textSecondary.withOpacity(0.7),
                              ),
                              const SizedBox(height: AppSpacing.large),
                              Text(
                                'No conversations yet',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.medium),
                          itemBuilder: (context, index) {
                            final c = _conversations[index];
                            final extra = _avatarExtras[c.otherParticipant.id];
                            final hasUnread = c.unreadCount > 0;
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: hasUnread
                                    ? AppColors.surface
                                    : Colors.transparent,
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 1,
                                ),
                              ),
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                leading: ProfileAvatar(
                                  radius: 22,
                                  imageUrl: extra?.url ??
                                      c.otherParticipant.profilePhotoUrl,
                                  memoryBytes: extra?.bytes ??
                                      decodeProfilePhotoBytes(
                                        c.otherParticipant.profilePhotoData,
                                      ),
                                  fallbackInitial: c.otherParticipant.username,
                                ),
                                title: Text(
                                  c.otherParticipant.username,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontWeight: hasUnread
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  c.lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _formatTime(c.lastMessageAt),
                                      style: AppTextStyles.bodySecondary,
                                    ),
                                    if (c.unreadCount > 0) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          c.unreadCount.toString(),
                                          style: AppTextStyles.bodySecondary
                                              .copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                onTap: () async {
                                  if (!isConversationDtoVisible(c)) {
                                    unawaited(_loadConversations());
                                    return;
                                  }
                                  try {
                                    final u = await _authService.getUserById(
                                      c.otherParticipant.id.toString(),
                                    );
                                    if (!mounted) return;
                                    if (u != null && u.isProfileViewBlocked) {
                                      unawaited(_loadConversations());
                                      return;
                                    }
                                  } on TargetUserNotAvailableException {
                                    if (mounted) unawaited(_loadConversations());
                                    return;
                                  } catch (_) {}
                                  if (!mounted) return;
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ChatDetailPage(conversation: c),
                                    ),
                                  );
                                  if (result == true) {
                                    await _loadConversations();
                                  }
                                },
                              ),
                            );
                          },
                        ),
          ),
          ),
        ],
      ),
    );
  }
}


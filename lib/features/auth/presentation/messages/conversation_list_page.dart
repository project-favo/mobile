import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/session_helper.dart';
import '../../../../core/utils/resolve_media_url.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/models/conversation_dto.dart';
import '../../data/services/auth_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
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
      // Tarihe göre (lastMessageAt) yukarıdan aşağı en yeni → en eski
      final sorted = [...page.content]..sort((a, b) {
          final da = DateTime.tryParse(a.lastMessageAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = DateTime.tryParse(b.lastMessageAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
      setState(() {
        _conversations = sorted;
        _isLoading = false;
      });
      _enrichConversationAvatars(sorted);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
    }
  }

  bool _participantHasLoadableAvatar(ConversationUserDto op) {
    final url = op.profilePhotoUrl?.trim();
    if (url != null && url.isNotEmpty) return true;
    final bytes = decodeProfilePhotoBytes(op.profilePhotoData);
    return bytes != null && bytes.isNotEmpty;
  }

  Future<void> _enrichConversationAvatars(List<ConversationDto> list) async {
    final updates = <int, ({String? url, Uint8List? bytes})>{};
    for (final c in list) {
      final op = c.otherParticipant;
      if (op.id <= 0) continue;
      if (_participantHasLoadableAvatar(op)) continue;
      if (_avatarExtras.containsKey(op.id)) continue;
      try {
        final u = await _authService.getUserById(op.id.toString());
        if (u == null) continue;
        final bytes = decodeProfilePhotoBytes(u.profilePhotoData);
        final url = u.profileImageUrl?.trim();
        if ((url != null && url.isNotEmpty) ||
            (bytes != null && bytes.isNotEmpty)) {
          updates[op.id] = (url: url, bytes: bytes);
        }
      } catch (_) {}
    }
    if (updates.isNotEmpty && mounted) {
      setState(() => _avatarExtras.addAll(updates));
    }
  }

  String _formatTime(String iso) {
    if (iso.length >= 16) {
      // "2025-03-04T14:30:00" -> "14:30"
      return iso.substring(11, 16);
    }
    return '';
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


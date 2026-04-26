import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/content_availability_messages.dart';
import '../../../../core/utils/content_unavailable_dialog.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/exceptions.dart';
import '../../../../core/utils/session_helper.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/config/app_background_timers.dart';
import '../../../../core/utils/resolve_media_url.dart';
import '../../../../core/utils/load_profile_image_bytes.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/models/conversation_dto.dart';
import '../../data/models/message_dto.dart';
import '../../data/services/auth_service.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../../../core/cache/chat_outgoing_user_cache.dart';
import '../../../../core/cache/current_user_cache.dart';
import '../../../../core/cache/message_list_cache.dart';
import '../../../../core/utils/user_profile_navigation.dart';
import '../../../../core/widgets/custom_snack_bar.dart';

class ChatDetailPage extends StatefulWidget {
  final ConversationDto conversation;
  /// Set when opening a new chat (no existing conversation id yet)
  final int? recipientId;

  const ChatDetailPage({super.key, required this.conversation, this.recipientId});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage>
    with WidgetsBindingObserver {
  final SessionHelper _sessionHelper = SessionHelper();
  final MessageRepository _messageRepository = MessageRepository();
  final AuthService _authService = AuthService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  late int _conversationId;
  /// İlk token / kullanıcı bilgisi gelene kadar tam ekran iskelet.
  bool _bootstrapping = true;
  /// Mesaj listesi henüz çekilirken (UI görünür, liste boş olabilir).
  bool _messagesLoading = false;
  bool _sendInFlight = false;
  String? _errorMessage;
  List<MessageDto> _messages = [];
  int? _currentUserId;
  String? _myAvatarUrl;
  Uint8List? _myAvatarBytes;
  String? _myInitial;
  late final Uint8List? _inlineOtherBytes;
  String? _resolvedOtherUrl;
  Uint8List? _resolvedOtherBytes;
  StompClient? _stompClient;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conversationId = widget.conversation.id;
    _inlineOtherBytes = decodeProfilePhotoBytes(
      widget.conversation.otherParticipant.profilePhotoData,
    );
    _init();
    _inputFocusNode.addListener(_onInputFocusChanged);
  }

  void _onInputFocusChanged() {
    if (_inputFocusNode.hasFocus) {
      _scrollToBottom();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Klavye / güvenli alan güncellemesi layout sırasında olur; aynı karede scroll tetikleme.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_bootstrapping &&
          !_messagesLoading &&
          _errorMessage == null &&
          _messages.isNotEmpty &&
          _isNearBottom()) {
        _scrollToBottom();
      }
    });
  }

  void _exitChatUserUnavailable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        showContentUnavailableDialog(
          context,
          title: kTitleUserUnavailable,
          message: kMessageUserUnavailableInChat,
          onContinue: () async {
            if (mounted) Navigator.of(context).pop();
          },
        ),
      );
    });
  }

  Future<void> _init() async {
    try {
      if (widget.conversation.otherParticipant.isAccountInactive) {
        _exitChatUserUnavailable();
        return;
      }
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Please login to see messages.');
      }
      // Sohbetler arası önbellek veya [CurrentUserCache] — getMe’yi kritik yolda bekleme
      if (ChatOutgoingUserCache.userId != null) {
        _currentUserId = ChatOutgoingUserCache.userId;
        _myAvatarUrl = ChatOutgoingUserCache.avatarUrl;
        _myAvatarBytes = ChatOutgoingUserCache.avatarBytes;
        _myInitial = ChatOutgoingUserCache.initial ?? '?';
      } else {
        final cu = CurrentUserCache.instance;
        if (cu.hasUserId) {
          _currentUserId = int.tryParse(cu.userId!);
          final n = cu.userName ?? '';
          _myInitial = n.isNotEmpty ? n[0].toUpperCase() : '?';
        }
        if (_currentUserId == null) {
          try {
            var me = await _authService.getMe();
            if (!me.hasProfileAvatarVisual && me.id.isNotEmpty) {
              final extra = await _authService.getUserById(me.id);
              me = me.withFilledAvatarFrom(extra);
            }
            _currentUserId = int.tryParse(me.id);
            _myAvatarUrl = me.profileImageUrl;
            _myAvatarBytes = decodeProfilePhotoBytes(me.profilePhotoData);
            _myInitial = me.userName.isNotEmpty ? me.userName[0].toUpperCase() : '?';
            _syncChatOutgoingCache();
          } catch (_) {}
        } else {
          unawaited(_fillAvatarsFromServer());
        }
      }
      if (_currentUserId != null) {
        _syncChatOutgoingCache();
      }
      unawaited(_enrichOtherParticipant());
      await _bootstrapExistingConversationIfNeeded();
      if (_conversationId > 0) {
        _connectStomp(token);
        if (mounted) {
          setState(() {
            _bootstrapping = false;
            _messagesLoading = true;
          });
        }
        await _loadMessages();
        _startPolling();
      } else {
        // Yeni konuşma (henüz backend’de yok) — ilk mesajı bekler
        if (mounted) setState(() => _bootstrapping = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _bootstrapping = false;
        _messagesLoading = false;
      });
    }
  }

  void _syncChatOutgoingCache() {
    ChatOutgoingUserCache.userId = _currentUserId;
    ChatOutgoingUserCache.avatarUrl = _myAvatarUrl;
    ChatOutgoingUserCache.avatarBytes = _myAvatarBytes;
    ChatOutgoingUserCache.initial = _myInitial;
  }

  Future<void> _fillAvatarsFromServer() async {
    try {
      var me = await _authService.getMe();
      if (!me.hasProfileAvatarVisual && me.id.isNotEmpty) {
        final extra = await _authService.getUserById(me.id);
        me = me.withFilledAvatarFrom(extra);
      }
      if (!mounted) return;
      setState(() {
        _myAvatarUrl = me.profileImageUrl;
        _myAvatarBytes = decodeProfilePhotoBytes(me.profilePhotoData);
        _myInitial = me.userName.isNotEmpty ? me.userName[0].toUpperCase() : '?';
        _syncChatOutgoingCache();
      });
    } catch (_) {}
  }

  /// Profil / sentetik konuşmadan açıldıysa, liste API’sinde zaten var olan thread’i bulur.
  Future<void> _bootstrapExistingConversationIfNeeded() async {
    if (_conversationId > 0) return;
    final rid = widget.recipientId;
    if (rid == null || rid <= 0) return;

    for (var page = 0; page < 6; page++) {
      try {
        final result =
            await _messageRepository.getConversations(page: page, size: 50);
        for (final c in result.content) {
          if (c.otherParticipant.id != rid) continue;
          if (c.id > 0) {
            _conversationId = c.id;
          }
          final op = c.otherParticipant;
          final url = op.profilePhotoUrl?.trim();
          final bytes = decodeProfilePhotoBytes(op.profilePhotoData);
          final hasListAvatar = (url != null && url.isNotEmpty) ||
              (bytes != null && bytes.isNotEmpty);
          if (hasListAvatar && mounted) {
            setState(() {
              _resolvedOtherUrl = url;
              _resolvedOtherBytes = bytes;
            });
          }
          return;
        }
        if (result.last || result.content.isEmpty) break;
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _enrichOtherParticipant() async {
    final op = widget.conversation.otherParticipant;
    if (op.id <= 0) return;
    try {
      final u = await _authService.getUserById(op.id.toString());
      if (!mounted) return;
      if (u == null) return;
      if (u.isProfileViewBlocked) {
        _exitChatUserUnavailable();
        return;
      }
      final pix = await _authService.fetchUserProfileImage(op.id.toString());
      if (!mounted) return;
      if (pix != null) {
        if (pix.isNotFound) {
          evictProfileImageBytesCacheForRaw(
            _resolvedOtherUrl ?? op.profilePhotoUrl,
          );
          setState(() {
            _resolvedOtherUrl = null;
            _resolvedOtherBytes = null;
          });
          return;
        }
        if (pix.hasImage) {
          final prevUrl = _resolvedOtherUrl ?? op.profilePhotoUrl;
          if (pix.memoryBytes != null) {
            evictProfileImageBytesCacheForRaw(prevUrl);
            if (mounted) {
              setState(() {
                _resolvedOtherBytes = pix.memoryBytes;
                _resolvedOtherUrl = null;
              });
            }
          } else {
            final nextUrl = pix.imageUrl?.trim();
            if (nextUrl != null && nextUrl.isNotEmpty) {
              if (prevUrl != nextUrl) {
                evictProfileImageBytesCacheForRaw(prevUrl);
              }
              evictProfileImageBytesCacheForRaw(nextUrl);
            }
            if (mounted) {
              setState(() {
                _resolvedOtherUrl = pix.imageUrl;
                _resolvedOtherBytes = null;
              });
            }
          }
          return;
        }
      }
      final bytes = decodeProfilePhotoBytes(u.profilePhotoData);
      final url = u.profileImageUrl?.trim();
      if ((url != null && url.isNotEmpty) ||
          (bytes != null && bytes.isNotEmpty)) {
        final prevUrl = _resolvedOtherUrl ?? op.profilePhotoUrl;
        if (url != null && url.isNotEmpty) {
          if (prevUrl != url) evictProfileImageBytesCacheForRaw(prevUrl);
          evictProfileImageBytesCacheForRaw(url);
        }
        if (mounted) {
          setState(() {
            _resolvedOtherUrl = url;
            _resolvedOtherBytes = bytes;
          });
        }
      }
    } on TargetUserNotAvailableException catch (_) {
      if (mounted) _exitChatUserUnavailable();
    } catch (_) {}
  }

  String? get _effectiveOtherUrl =>
      _resolvedOtherUrl ?? widget.conversation.otherParticipant.profilePhotoUrl;

  Uint8List? get _effectiveOtherBytes =>
      _resolvedOtherBytes ?? _inlineOtherBytes;

  Future<void> _loadMessages() async {
    if (!mounted) return;
    // Cache'de mesaj varsa hemen göster
    final cached = MessageListCache.instance.peek(_conversationId);
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _messages = cached;
        _messagesLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      unawaited(_refreshMessagesInBackground());
      return;
    }

    setState(() {
      _errorMessage = null;
      _messagesLoading = true;
    });
    try {
      final page = await _messageRepository.getConversationMessages(
        conversationId: _conversationId,
        page: 0,
        size: 50,
      );
      if (!mounted) return;
      MessageListCache.instance.remember(_conversationId, page.content);
      setState(() {
        _messages = page.content;
        _messagesLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _messagesLoading = false;
      });
    }
  }

  Future<void> _refreshMessagesInBackground() async {
    try {
      final page = await _messageRepository.getConversationMessages(
        conversationId: _conversationId,
        page: 0,
        size: 50,
      );
      if (!mounted) return;
      MessageListCache.instance.remember(_conversationId, page.content);
      // Sadece yeni mesaj varsa güncelle
      final fresh = page.content;
      final hasNew = fresh.length != _messages.length ||
          (fresh.isNotEmpty && _messages.isNotEmpty && fresh.last.id != _messages.last.id);
      if (hasNew) {
        setState(() => _messages = fresh);
        if (_isNearBottom()) _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sendInFlight) return;
    final uid = _currentUserId;
    if (uid == null) {
      CustomSnackBar.show(
        context,
        message: 'Please wait, loading your profile…',
        variant: CustomSnackBarVariant.neutral,
      );
      return;
    }

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final optimistic = MessageDto(
      id: tempId,
      conversationId: _conversationId,
      senderId: uid,
      senderUsername: '',
      content: text,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      isRead: true,
    );

    _controller.clear();
    setState(() => _messages = [..._messages, optimistic]);
    _scrollToBottom();

    _sendInFlight = true;
    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Failed to get Firebase ID token');
      }
      final msg = await _messageRepository.sendMessage(
        conversationId: _conversationId > 0 ? _conversationId : null,
        recipientId: _conversationId == 0 ? widget.recipientId : null,
        content: text,
      );
      // First message in a new conversation — bootstrap real-time
      if (_conversationId == 0 && msg.conversationId > 0) {
        _conversationId = msg.conversationId;
        final t2 = await _sessionHelper.ensureSession();
        if (t2 != null) {
          _connectStomp(t2);
          _startPolling();
        }
      }
      if (!mounted) return;
      setState(() {
        final withoutTemp = _messages.where((m) => m.id != tempId).toList();
        if (!withoutTemp.any((m) => m.id == msg.id)) {
          _messages = [...withoutTemp, msg];
        } else {
          _messages = withoutTemp;
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((m) => m.id != tempId).toList();
      });
      final msg = ErrorHandler.getUserFriendlyMessage(e);
      CustomSnackBar.show(
        context,
        message: msg,
        variant: CustomSnackBarVariant.error,
      );
    } finally {
      _sendInFlight = false;
    }
  }

  @override
  void dispose() {
    _inputFocusNode.removeListener(_onInputFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _stompClient?.deactivate();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(AppBackgroundTimers.chatThreadPoll, (_) {
      _refreshMessagesSilently();
    });
  }

  Future<void> _refreshMessagesSilently() async {
    try {
      if (_conversationId == 0) return;
      final page = await _messageRepository.getConversationMessages(
        conversationId: _conversationId,
        page: 0,
        size: 50,
      );
      if (!mounted) return;
      final fresh = page.content;
      final hadNew = fresh.length != _messages.length ||
          (fresh.isNotEmpty &&
              _messages.isNotEmpty &&
              fresh.last.id != _messages.last.id);
      // Kullanıcı yukarı kaydırdıysa ve yeni mesaj yoksa konumu sıfırlama.
      final shouldScroll = hadNew || _isNearBottom();
      setState(() {
        _messages = fresh;
      });
      if (shouldScroll) _scrollToBottom();
    } catch (_) {
      // Sessizce yut; real-time için sadece best-effort polling
    }
  }

  void _connectStomp(String token) {
    // Base URL -> WebSocket URL (http -> ws, https -> wss)
    String wsBase = ApiConfig.baseUrl;
    if (wsBase.startsWith('https://')) {
      wsBase = wsBase.replaceFirst('https://', 'wss://');
    } else if (wsBase.startsWith('http://')) {
      wsBase = wsBase.replaceFirst('http://', 'ws://');
    }

    _stompClient = StompClient(
      config: StompConfig(
        url: '$wsBase/ws',
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        onConnect: _onStompConnected,
        onWebSocketError: (dynamic error) {
          // Real-time bağlantı kurulamazsa sessizce geç; REST ile çalışmaya devam eder
        },
        onStompError: (StompFrame frame) {
          // İstersen burada debug log tutabilirsin
        },
      ),
    );

    _stompClient?.activate();
  }

  void _onStompConnected(StompFrame frame) {
    _stompClient?.subscribe(
      destination: '/queue/conversations/$_conversationId',
      callback: (StompFrame frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        try {
          final Map<String, dynamic> data =
              jsonDecode(body) as Map<String, dynamic>;
          final incoming = MessageDto.fromJson(data);
          if (!mounted) return;
          final isNew = !_messages.any((m) => m.id == incoming.id);
          setState(() {
            if (isNew) _messages = [..._messages, incoming];
          });
          if (isNew || _isNearBottom()) _scrollToBottom();
        } catch (_) {
          // JSON parse hatası olursa görmezden gel
        }
      },
    );
  }

  Widget _buildOtherAvatar({required double size}) {
    final initial = widget.conversation.otherParticipant.username.isNotEmpty
        ? widget.conversation.otherParticipant.username[0].toUpperCase()
        : '?';
    return ProfileAvatarImage(
      size: size,
      imageUrl: _effectiveOtherUrl,
      memoryBytes: _effectiveOtherBytes,
      fallbackInitial: initial,
    );
  }

  Widget _buildMyAvatar({required double size}) {
    return ProfileAvatarImage(
      size: size,
      imageUrl: _myAvatarUrl,
      memoryBytes: _myAvatarBytes,
      fallbackInitial: _myInitial ?? '?',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(true),
        ),
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final other = widget.conversation.otherParticipant;
            if (other.id <= 0) return;
            openUserProfileIfActive(
              context,
              userId: other.id.toString(),
              userName: other.username,
              profileImageUrl: _effectiveOtherUrl,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatarImage(
                size: 32,
                imageUrl: _effectiveOtherUrl,
                memoryBytes: _effectiveOtherBytes,
                fallbackInitial: widget.conversation.otherParticipant.username,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.conversation.otherParticipant.username,
                  style: AppTextStyles.heading3.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/background.png', fit: BoxFit.cover),
          ),
          GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            Expanded(
              child: _bootstrapping
                ? ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.large),
                    itemCount: 8,
                    itemBuilder: (context, index) {
                      final isMine = index.isEven;
                      final maxWidth =
                          MediaQuery.of(context).size.width * 0.7;
                      const otherAvatarSize = 34.0;
                      const myAvatarSize = 28.0;
                      final bubbleHeight =
                          index % 3 == 1 ? 36.0 : 20.0;
                      Widget circleSkeleton(double size) => ClipOval(
                            child: SkeletonLoader(
                              width: size,
                              height: size,
                              borderRadius:
                                  BorderRadius.circular(size / 2),
                            ),
                          );
                      final bubble = ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: SkeletonLoader(
                          width: double.infinity,
                          height: bubbleHeight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      );
                      return Container(
                        margin: const EdgeInsets.only(
                          bottom: AppSpacing.small,
                        ),
                        child: Row(
                          mainAxisAlignment: isMine
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: isMine
                              ? [
                                  bubble,
                                  const SizedBox(width: 8),
                                  circleSkeleton(myAvatarSize),
                                ]
                              : [
                                  circleSkeleton(otherAvatarSize),
                                  const SizedBox(width: 10),
                                  bubble,
                                ],
                        ),
                      );
                    },
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xLarge),
                          child: Text(
                            _errorMessage!,
                            style: AppTextStyles.bodySecondary.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.large),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final m = _messages[index];
                          final isMine = _currentUserId != null &&
                              m.senderId == _currentUserId;
                          final bgColor =
                              isMine ? AppColors.primary : AppColors.surface;
                          final textColor =
                              isMine ? Colors.white : AppColors.textPrimary;
                          final maxWidth =
                              MediaQuery.of(context).size.width * 0.7;

                          // Avatar sadece ardışık grup içindeki son mesajda görünür.
                          final isLastInGroup = index == _messages.length - 1 ||
                              _messages[index + 1].senderId != m.senderId;

                          final bubble = ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.large,
                                vertical: AppSpacing.medium,
                              ),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                m.content,
                                style: AppTextStyles.body.copyWith(
                                  color: textColor,
                                ),
                              ),
                            ),
                          );

                          Widget myAvatarOrGap() => isLastInGroup
                              ? _buildMyAvatar(size: 28)
                              : const SizedBox(width: 28);
                          Widget otherAvatarOrGap() => isLastInGroup
                              ? _buildOtherAvatar(size: 34)
                              : const SizedBox(width: 34);

                          final messageRow = Row(
                            mainAxisAlignment: isMine
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: isMine
                                ? [bubble, const SizedBox(width: 8), myAvatarOrGap()]
                                : [otherAvatarOrGap(), const SizedBox(width: 10), bubble],
                          );

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_shouldShowDateSeparator(index))
                                _DateSeparator(label: _formatDateLabel(m.createdAt)),
                              _SwipeableMessageRow(
                                isFromMe: isMine,
                                timeLabel: _formatTimeLabel(m.createdAt),
                                bottomMargin: isLastInGroup
                                    ? AppSpacing.medium
                                    : AppSpacing.small / 2,
                                child: messageRow,
                              ),
                            ],
                          );
                        },
                      ),
                          if (_messagesLoading && _messages.isEmpty)
                            const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                        ],
                      ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.large,
                  AppSpacing.medium,
                  AppSpacing.large,
                  AppSpacing.large,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _inputFocusNode,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.small),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppColors.primary),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
        ],
      ),
    );
  }

  // ── Mesaj zaman / tarih yardımcıları ────────────────────────────────────────

  String _formatTimeLabel(String createdAt) {
    try {
      final s = createdAt.trim();
      // Backend LocalDateTime → 'Z' suffix yok → UTC olarak zorla.
      final utcStr = (s.contains('Z') || s.contains('+')) ? s : '${s}Z';
      final dt = DateTime.parse(utcStr).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  String _formatDateLabel(String createdAt) {
    try {
      final s = createdAt.trim();
      final utcStr = (s.contains('Z') || s.contains('+')) ? s : '${s}Z';
      final dt = DateTime.parse(utcStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(msgDay).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      if (diff < 7) {
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        return days[dt.weekday - 1];
      }
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final yearSuffix = dt.year != now.year ? ' ${dt.year}' : '';
      return '${dt.day} ${months[dt.month - 1]}$yearSuffix';
    } catch (_) {
      return '';
    }
  }

  bool _shouldShowDateSeparator(int index) {
    if (index == 0) return true;
    try {
      final curr = DateTime.parse(_messages[index].createdAt).toLocal();
      final prev = DateTime.parse(_messages[index - 1].createdAt).toLocal();
      return curr.year != prev.year ||
          curr.month != prev.month ||
          curr.day != prev.day;
    } catch (_) {
      return false;
    }
  }

  /// Kullanıcı zaten alta yakınsa true. Kaydırma kararı buna göre alınır.
  bool _isNearBottom({double threshold = 120}) {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < threshold;
  }

  void _scrollToBottom() {
    if (!mounted) return;
    void jump() {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (!max.isFinite) return;
      _scrollController.jumpTo(max);
    }

    // Ardışık karelerde tekrarla: klavye animasyonu sırasında extent her karede artabilir.
    // [mounted] yoksa zinciri kes — dispose sonrası kare planlaması Inherited assert patlatır.
    void scheduleChained(int remaining) {
      if (remaining <= 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        jump();
        if (!mounted) return;
        scheduleChained(remaining - 1);
      });
    }

    scheduleChained(4);
  }
}

// ── Swipe-to-reveal timestamp ────────────────────────────────────────────────

class _SwipeableMessageRow extends StatefulWidget {
  final Widget child;
  final String timeLabel;
  final double bottomMargin;
  /// Kendi mesajlarında sola kaydırınca sağda saat; karşı mesajlarda sağa kaydırınca solda saat.
  final bool isFromMe;

  const _SwipeableMessageRow({
    required this.child,
    required this.timeLabel,
    required this.bottomMargin,
    required this.isFromMe,
  });

  @override
  State<_SwipeableMessageRow> createState() => _SwipeableMessageRowState();
}

class _SwipeableMessageRowState extends State<_SwipeableMessageRow>
    with SingleTickerProviderStateMixin {
  double _offset = 0;
  late final AnimationController _snapCtrl;
  late Animation<double> _snapAnim;

  static const double _maxDrag = 72;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _snapCtrl.stop();
    setState(() {
      if (widget.isFromMe) {
        _offset = (_offset + d.delta.dx).clamp(-_maxDrag, 0.0);
      } else {
        _offset = (_offset + d.delta.dx).clamp(0.0, _maxDrag);
      }
    });
  }

  void _onDragEnd(DragEndDetails _) {
    final start = _offset;
    _snapAnim = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic),
    )..addListener(() => setState(() => _offset = _snapAnim.value));
    _snapCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final opacity = widget.isFromMe
        ? (-_offset / _maxDrag).clamp(0.0, 1.0)
        : (_offset / _maxDrag).clamp(0.0, 1.0);
    final stackAlign =
        widget.isFromMe ? Alignment.centerRight : Alignment.centerLeft;
    final timePadding = widget.isFromMe
        ? const EdgeInsets.only(right: 6, bottom: 2)
        : const EdgeInsets.only(left: 6, bottom: 2);

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      // opaque: gesture'ı kesinlikle bu widget yakalar, arena'ya bırakmaz.
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: stackAlign,
          children: [
            Opacity(
              opacity: opacity,
              child: Padding(
                padding: timePadding,
                child: Text(
                  widget.timeLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: widget.bottomMargin),
              child: Transform.translate(
                offset: Offset(_offset, 0),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Date separator ───────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  final String label;
  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.white.withOpacity(0.3),
              thickness: 1,
              endIndent: 10,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.white.withOpacity(0.3),
              thickness: 1,
              indent: 10,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/session_helper.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/utils/resolve_media_url.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/models/conversation_dto.dart';
import '../../data/models/message_dto.dart';
import '../../data/services/auth_service.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../../core/widgets/profile_avatar.dart';

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
  bool _isLoading = true;
  bool _isSending = false;
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
    // Klavye açılıp kapanınca viewport yeniden boyanıyor; birkaç kare boyunca
    // maxScrollExtent güncellenir, tek seferde jumpTo yetmiyor.
    if (!_isLoading && _errorMessage == null && _messages.isNotEmpty) {
      _scrollToBottom();
    }
  }

  Future<void> _init() async {
    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Please login to see messages.');
      }
      // Backend current user id'yi al (senderId ile karşılaştırmak için)
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
      } catch (_) {}
      await _bootstrapExistingConversationIfNeeded();
      await _enrichOtherParticipant();
      if (_conversationId > 0) {
        _connectStomp(token);
        await _loadMessages();
        _startPolling();
      } else {
        // Yeni konuşma (henüz backend’de yok) — ilk mesajı bekler
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
    }
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
              _resolvedOtherUrl ??= url;
              _resolvedOtherBytes ??= bytes;
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

  bool _otherParticipantHasLoadableVisual(ConversationUserDto op) {
    final url = op.profilePhotoUrl?.trim();
    if (url != null && url.isNotEmpty) return true;
    final inline = _inlineOtherBytes;
    if (inline != null && inline.isNotEmpty) return true;
    return false;
  }

  Future<void> _enrichOtherParticipant() async {
    final op = widget.conversation.otherParticipant;
    if (_otherParticipantHasLoadableVisual(op)) return;
    if (op.id <= 0) return;
    try {
      final u = await _authService.getUserById(op.id.toString());
      if (u == null || !mounted) return;
      final bytes = decodeProfilePhotoBytes(u.profilePhotoData);
      final url = u.profileImageUrl?.trim();
      if ((url != null && url.isNotEmpty) ||
          (bytes != null && bytes.isNotEmpty)) {
        setState(() {
          _resolvedOtherUrl = url;
          _resolvedOtherBytes = bytes;
        });
      }
    } catch (_) {}
  }

  String? get _effectiveOtherUrl =>
      _resolvedOtherUrl ?? widget.conversation.otherParticipant.profilePhotoUrl;

  Uint8List? get _effectiveOtherBytes =>
      _resolvedOtherBytes ?? _inlineOtherBytes;

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final page = await _messageRepository.getConversationMessages(
        conversationId: _conversationId,
        page: 0,
        size: 50,
      );
      if (!mounted) return;
      setState(() {
        // Backend'den gelen sırayı koru: eski mesajlar üstte, yeniler altta
        _messages = page.content;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
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
        final token = await _sessionHelper.ensureSession();
        if (token != null) {
          _connectStomp(token);
          _startPolling();
        }
      }
      if (!mounted) return;
      _controller.clear();
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [..._messages, msg];
        }
        _isSending = false;
      });
      // Backend sırasını ve olası ekstra alanları eşitlemek için sessizce güncelle
      _refreshMessagesSilently();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final msg = ErrorHandler.getUserFriendlyMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _isSending = false);
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
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
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
      setState(() {
        _messages = page.content;
      });
      // Her sessiz yenilemeden sonra da en güncel mesaja kaydır
      _scrollToBottom();
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
          setState(() {
            if (!_messages.any((m) => m.id == incoming.id)) {
              _messages = [..._messages, incoming];
            }
          });
          _scrollToBottom();
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
        title: Row(
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
              child: _isLoading
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
                    : ListView.builder(
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

                          return Container(
                            margin: const EdgeInsets.only(bottom: AppSpacing.small),
                            child: Row(
                              mainAxisAlignment: isMine
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: isMine
                                  ? [bubble, const SizedBox(width: 8), _buildMyAvatar(size: 28)]
                                  : [_buildOtherAvatar(size: 34), const SizedBox(width: 10), bubble],
                            ),
                          );
                        },
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
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : const Icon(Icons.send, color: AppColors.primary),
                      onPressed: _isSending ? null : _sendMessage,
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

  void _scrollToBottom() {
    void jump() {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (!max.isFinite) return;
      _scrollController.jumpTo(max);
    }

    // Ardışık karelerde tekrarla: klavye animasyonu sırasında extent her karede artabilir.
    void scheduleChained(int remaining) {
      if (remaining <= 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        jump();
        scheduleChained(remaining - 1);
      });
    }

    scheduleChained(4);
  }
}


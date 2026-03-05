import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/session_helper.dart';
import '../../../../core/config/api_config.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/models/conversation_dto.dart';
import '../../data/models/message_dto.dart';
import '../../data/services/auth_service.dart';

class ChatDetailPage extends StatefulWidget {
  final ConversationDto conversation;

  const ChatDetailPage({super.key, required this.conversation});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final SessionHelper _sessionHelper = SessionHelper();
  final MessageRepository _messageRepository = MessageRepository();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  List<MessageDto> _messages = [];
  int? _currentUserId;
  StompClient? _stompClient;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Please login to see messages.');
      }
      // Backend current user id'yi al (senderId ile karşılaştırmak için)
      try {
        final authService = AuthService();
        final me = await authService.getMe();
        _currentUserId = int.tryParse(me.id);
      } catch (_) {}
      _connectStomp(token);
      await _loadMessages();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final page = await _messageRepository.getConversationMessages(
        conversationId: widget.conversation.id,
        page: 0,
        size: 50,
      );
      if (!mounted) return;
      setState(() {
        _messages = page.content;
        _isLoading = false;
      });
      // En sona kaydır
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
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
        conversationId: widget.conversation.id,
        content: text,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [..._messages, msg];
        }
        _isSending = false;
      });
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
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
    _controller.dispose();
    _scrollController.dispose();
    _stompClient?.deactivate();
    super.dispose();
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
      config: StompConfig.SockJS(
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
      destination: '/queue/conversations/${widget.conversation.id}',
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
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        } catch (_) {
          // JSON parse hatası olursa görmezden gel
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: (widget.conversation.otherParticipant
                              .profilePhotoUrl !=
                          null &&
                      widget.conversation.otherParticipant.profilePhotoUrl!
                          .isNotEmpty)
                  ? NetworkImage(widget
                      .conversation.otherParticipant.profilePhotoUrl!)
                  : null,
              child: (widget.conversation.otherParticipant.profilePhotoUrl ==
                          null ||
                      widget.conversation.otherParticipant.profilePhotoUrl!
                          .isEmpty)
                  ? Text(
                      widget.conversation.otherParticipant.username.isNotEmpty
                          ? widget.conversation.otherParticipant.username[0]
                              .toUpperCase()
                          : '?',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              widget.conversation.otherParticipant.username,
              style: AppTextStyles.heading3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
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
                          final align = isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft;
                          final color =
                              isMine ? AppColors.primary : AppColors.surface;
                          final textColor = isMine
                              ? Colors.white
                              : AppColors.textPrimary;
                          final maxWidth = MediaQuery.of(context).size.width *
                              0.7; // WhatsApp benzeri genişlik
                          return Align(
                            alignment: align,
                            child: Container(
                              margin: EdgeInsets.only(
                                bottom: AppSpacing.small,
                                left: isMine ? 64 : 0,
                                right: isMine ? 0 : 64,
                              ),
                              child: ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: maxWidth),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.large,
                                    vertical: AppSpacing.medium,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    m.content,
                                    style: AppTextStyles.body.copyWith(
                                      color: textColor,
                                    ),
                                  ),
                                ),
                              ),
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
    );
  }
}


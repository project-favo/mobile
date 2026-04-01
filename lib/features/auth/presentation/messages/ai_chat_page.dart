import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/network/api_client.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final SessionHelper _sessionHelper = SessionHelper();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isSending = false;

  /// Basit mesaj modeli: role = 'user' veya 'assistant'
  final List<_AiMessage> _messages = [
    const _AiMessage(
      role: 'assistant',
      text:
          'Merhaba, ben FAVO asistanıyım. Ürünler, yorumlar veya uygulama ile ilgili sorularını buradan yazabilirsin.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus) {
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _messages.add(_AiMessage(role: 'user', text: text));
    });
    _controller.clear();
    _scrollToBottom();

    try {
      // Token ve Authorization header
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Please login to use the assistant.');
      }

      final apiClient = ApiClient();
      // ApiClient zaten initialize edilmiş olmalı; diğer yerlerde olduğu gibi kullanıyoruz
      final response = await apiClient.dio.post(
        '/api/chat',
        data: {'message': text},
      );

      final data = response.data;
      final replyText = (data is Map && data['reply'] is String)
          ? data['reply'] as String
          : 'Yanıt alınamadı, lütfen tekrar dener misin?';

      if (!mounted) return;
      setState(() {
        _messages.add(_AiMessage(role: 'assistant', text: replyText));
        _isSending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final msg = ErrorHandler.getUserFriendlyMessage(e);
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Text(
          'FAVO Assistant',
          style: AppTextStyles.heading3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppSpacing.large),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final m = _messages[index];
                  final isUser = m.role == 'user';
                  final align =
                      isUser ? Alignment.centerRight : Alignment.centerLeft;
                  final bgColor =
                      isUser ? AppColors.primary : AppColors.surface;
                  final textColor =
                      isUser ? Colors.white : AppColors.textPrimary;
                  final maxWidth =
                      MediaQuery.of(context).size.width * 0.7; // chat bubble

                  return Align(
                    alignment: align,
                    child: Container(
                      margin: EdgeInsets.only(
                        bottom: AppSpacing.small,
                        left: isUser ? 64 : 0,
                        right: isUser ? 0 : 64,
                      ),
                      child: ConstrainedBox(
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
                            m.text,
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
                        focusNode: _inputFocusNode,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Mesajını yaz...',
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
    );
  }
}

class _AiMessage {
  final String role;
  final String text;

  const _AiMessage({
    required this.role,
    required this.text,
  });
}


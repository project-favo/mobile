import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_decorations.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/utils/resolve_media_url.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/routes/custom_page_transitions.dart';
import '../../data/services/auth_service.dart';
import '../../data/models/product_dto.dart';
import '../../data/models/tag_dto.dart';
import '../review/pages/review_page.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final SessionHelper _sessionHelper = SessionHelper();
  final AuthService _authService = AuthService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isSending = false;
  late final AnimationController _logoController;
  String? _userAvatarUrl;
  Uint8List? _userAvatarBytes;
  String? _userInitial;
  bool _userScrolledUp = false; // kullanıcı yukarı kaydırdıysa auto-scroll durdur

  late final List<_AiMessage> _messages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final restored = _AiChatTranscriptCache.loadIfFresh();
    _messages =
        restored ??
        [
          _AiMessage(
            role: 'assistant',
            text:
                "Hi, I'm the FAVO assistant. You can ask anything here about products, reviews, or the app.",
          ),
        ];
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scrollController.addListener(_onScrollChanged);

    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      var me = await _authService.getMe();
      if (!me.hasProfileAvatarVisual && me.id.isNotEmpty) {
        final extra = await _authService.getUserById(me.id);
        me = me.withFilledAvatarFrom(extra);
      }
      if (!mounted) return;
      setState(() {
        _userAvatarUrl = me.profileImageUrl;
        _userAvatarBytes = decodeProfilePhotoBytes(me.profilePhotoData);
        _userInitial =
            (me.userName.isNotEmpty) ? me.userName[0].toUpperCase() : '?';
      });
    } catch (_) {}
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 80;
    _userScrolledUp = !atBottom;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _AiChatTranscriptCache.save(_messages);
    _logoController.dispose();
    _controller.dispose();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<Response<dynamic>> _callChatApi(String text) {
    return ApiClient().dio.post('/api/chat', data: {'message': text});
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _messages.add(_AiMessage(role: 'user', text: text));
    });
    _controller.clear();
    _userScrolledUp = false; // mesaj gönderilince en alta dön
    _scrollToBottom();

    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Please login to use the assistant.');
      }

      Response<dynamic> response;
      try {
        response = await _callChatApi(text);
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          // Token expired — force refresh and retry once
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) rethrow;
          final newToken = await user.getIdToken(true);
          if (newToken == null) rethrow;
          ApiClient().setAuthToken(newToken);
          response = await _callChatApi(text);
        } else {
          rethrow;
        }
      }

      final data = response.data;
      final replyText = (data is Map && data['reply'] is String)
          ? data['reply'] as String
          : 'No reply received. Please try again.';

      final products = _parseProducts(data);

      if (!mounted) return;
      setState(() {
        _messages.add(
          _AiMessage(role: 'assistant', text: replyText, products: products),
        );
        _isSending = false;
      });
      // Sadece kullanıcı zaten en alttaysa aşağıya git
      if (!_userScrolledUp) _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final msg = ErrorHandler.getUserFriendlyMessage(e);
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    }
  }

  List<_AiProduct> _parseProducts(dynamic data) {
    if (data is! Map) return [];
    final raw = data['products'];
    if (raw is! List || raw.isEmpty) return [];
    final result = <_AiProduct>[];
    for (final item in raw) {
      if (item is! Map) continue;
      result.add(
        _AiProduct(
          id: item['id']?.toString() ?? '',
          name: item['name']?.toString() ?? '',
          imageURL: item['imageURL']?.toString() ?? '',
          tagName: item['tagName']?.toString() ?? '',
          averageRating: item['averageRating'] != null
              ? (item['averageRating'] is num
                  ? (item['averageRating'] as num).toDouble()
                  : double.tryParse(item['averageRating'].toString()) ?? 0.0)
              : 0.0,
          reviewCount: item['reviewCount'] != null
              ? (item['reviewCount'] is int
                  ? item['reviewCount'] as int
                  : int.tryParse(item['reviewCount'].toString()) ?? 0)
              : 0,
        ),
      );
    }
    return result;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (!pos.hasContentDimensions) return;
      _scrollController.animateTo(
        pos.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildAssistantAvatar({required double size}) {
    return AnimatedBuilder(
      animation: _logoController,
      builder: (context, child) {
        final v = _logoController.value;
        final scale = 1.0 + (0.05 * (1 - (2 * v - 1).abs()));
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: 0.1),
        ),
        padding: EdgeInsets.all(size * 0.1),
        child: Image.asset('assets/images/Chatbot.png', fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildUserAvatar({required double size}) {
    return ProfileAvatarImage(
      size: size,
      imageUrl: _userAvatarUrl,
      memoryBytes: _userAvatarBytes,
      fallbackInitial: _userInitial ?? '?',
    );
  }

  Widget _buildProductStrip(List<_AiProduct> products) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.medium),
        itemBuilder: (context, i) => _ProductChip(
          product: products[i],
          onTap: () => Navigator.push(
            context,
            SlideRightRoute(
              page: ReviewPage(
                product: ProductDto(
                  id: products[i].id,
                  name: products[i].name,
                  imageURL: products[i].imageURL,
                  tag: TagDto(id: '', name: products[i].tagName),
                  averageRating: products[i].averageRating,
                ),
              ),
            ),
          ),
        ),
      ),
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
        automaticallyImplyLeading: true,
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
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppSpacing.large),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final m = _messages[index];
                  final isUser = m.role == 'user';
                  final bgColor =
                      isUser ? AppColors.primary : AppColors.surface;
                  final textColor =
                      isUser ? Colors.white : AppColors.textPrimary;
                  final maxWidth = MediaQuery.of(context).size.width * 0.7;

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
                        m.text,
                        style:
                            AppTextStyles.body.copyWith(color: textColor),
                      ),
                    ),
                  );

                  if (!isUser) {
                    return Container(
                      margin:
                          const EdgeInsets.only(bottom: AppSpacing.small),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _buildAssistantAvatar(size: 34),
                              const SizedBox(width: 10),
                              bubble,
                            ],
                          ),
                          if (m.products.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.small),
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 44), // avatar width + gap
                              child: _buildProductStrip(m.products),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return Container(
                    margin:
                        const EdgeInsets.only(bottom: AppSpacing.small),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        bubble,
                        const SizedBox(width: 10),
                        _buildUserAvatar(size: 26),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: AnimatedPadding(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: EdgeInsets.fromLTRB(
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
                        hintText: 'Type your message...',
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
}

// ─── Models ──────────────────────────────────────────────────────────────────

class _AiMessage {
  final String role;
  final String text;
  final List<_AiProduct> products;

  _AiMessage({
    required this.role,
    required this.text,
    this.products = const [],
  });
}

class _AiProduct {
  final String id;
  final String name;
  final String imageURL;
  final String tagName;
  final double averageRating;
  final int reviewCount;

  const _AiProduct({
    required this.id,
    required this.name,
    required this.imageURL,
    required this.tagName,
    required this.averageRating,
    required this.reviewCount,
  });
}

// ─── Product chip in chat ─────────────────────────────────────────────────────

class _ProductChip extends StatelessWidget {
  final _AiProduct product;
  final VoidCallback onTap;

  const _ProductChip({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppDecorations.softCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Container(
                height: 80,
                width: 110,
                color: AppColors.background,
                child: product.imageURL.isNotEmpty
                    ? Image.network(
                        product.imageURL,
                        height: 80,
                        width: 110,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
              child: Text(
                product.name,
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Builder(
                builder: (context) {
                  final hasRating = product.averageRating > 0.001 &&
                      !product.averageRating.isNaN &&
                      !product.averageRating.isInfinite;
                  if (!hasRating && product.reviewCount <= 0) {
                    return Text(
                      'New',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    );
                  }
                  return Row(
                    children: [
                      if (hasRating) ...[
                        const Icon(Icons.star_rounded,
                            size: 12, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          product.averageRating.toStringAsFixed(1),
                          style:
                              AppTextStyles.bodySmall.copyWith(fontSize: 11),
                        ),
                      ],
                      if (product.reviewCount > 0) ...[
                        if (hasRating) const SizedBox(width: 3),
                        Text(
                          '(${product.reviewCount})',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: 80,
      width: 110,
      color: AppColors.primary.withValues(alpha: 0.08),
      child: const Icon(Icons.image_not_supported_outlined,
          color: AppColors.textSecondary),
    );
  }
}

/// Son oturum sohbeti (sayfadan çıkıp tekrar girince ~40 dk’ya kadar).
class _AiChatTranscriptCache {
  static List<_AiMessage>? _lines;
  static DateTime? _savedAt;
  static const Duration _ttl = Duration(minutes: 40);

  static void save(List<_AiMessage> src) {
    _lines = [
      for (final m in src)
        _AiMessage(
          role: m.role,
          text: m.text,
          products: List<_AiProduct>.from(m.products),
        ),
    ];
    _savedAt = DateTime.now();
  }

  static List<_AiMessage>? loadIfFresh() {
    if (_lines == null || _savedAt == null) return null;
    if (DateTime.now().difference(_savedAt!) > _ttl) {
      _lines = null;
      _savedAt = null;
      return null;
    }
    return [
      for (final m in _lines!)
        _AiMessage(
          role: m.role,
          text: m.text,
          products: List<_AiProduct>.from(m.products),
        ),
    ];
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/session_helper.dart';
import '../../../routes/app_routes.dart';
import '../data/models/register_request_dto.dart';
import '../data/services/auth_service.dart';

/// Kayıt öncesi e-posta doğrulama sayfası.
///
/// Kullanıcı henüz Firebase veya DB'ye kaydedilmemiştir.
/// Doğru kodu girince → Firebase kullanıcısı oluşturulur → backend kaydı yapılır → giriş tamamlanır.
/// Geri tuşu: temizlenecek bir şey yok, direkt [RegisterPage]'e döner.
class PreRegisterVerifyPage extends StatefulWidget {
  final String email;
  final String password;
  final RegisterRequestDto pendingRegistration;

  const PreRegisterVerifyPage({
    super.key,
    required this.email,
    required this.password,
    required this.pendingRegistration,
  });

  @override
  State<PreRegisterVerifyPage> createState() => _PreRegisterVerifyPageState();
}

class _PreRegisterVerifyPageState extends State<PreRegisterVerifyPage> {
  final _authService = AuthService();
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  final _scrollController = ScrollController();

  bool _busy = false;
  bool _resendBusy = false;
  final ValueNotifier<int> _cooldownNotifier = ValueNotifier(60);
  Timer? _cooldownTimer;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _cooldownNotifier.value = 60;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCooldownTimer();
      _codeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _cooldownNotifier.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    if (_cooldownNotifier.value <= 0) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      final v = _cooldownNotifier.value;
      if (v <= 1) { _cooldownNotifier.value = 0; t.cancel(); }
      else { _cooldownNotifier.value = v - 1; }
    });
  }

  Future<void> _resend() async {
    if (_resendBusy || _cooldownNotifier.value > 0) return;
    setState(() { _resendBusy = true; _statusMessage = null; });
    try {
      await _authService.sendPreRegistrationCode(widget.email);
      if (!mounted) return;
      setState(() => _resendBusy = false);
      _cooldownNotifier.value = 60;
      _startCooldownTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resendBusy = false;
        _statusMessage = ErrorHandler.getUserFriendlyMessage(e);
      });
    }
  }

  String _combinedCode() =>
      _codeController.text.replaceAll(RegExp(r'\D'), '').trim();

  String _formatCountdown(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _verifyAndRegister() async {
    final code = _combinedCode();
    if (code.length != 5 || !RegExp(r'^\d{5}$').hasMatch(code)) {
      setState(() => _statusMessage = 'Enter the full 5-digit code.');
      return;
    }

    setState(() { _busy = true; _statusMessage = null; });
    try {
      // 1. Kodu doğrula
      await _authService.verifyPreRegistrationCode(widget.email, code);

      // 2. Firebase kullanıcısı oluştur
      await _authService.createFirebaseUserForRegistration(
        email: widget.email,
        password: widget.password,
      );

      // 3. Backend'e kayıt yap (emailVerified=true olarak döner)
      await _authService.registerOnBackend(widget.pendingRegistration);

      // 4. Backend oturumu kur
      await _authService.establishBackendSession();
      SessionHelper().markBackendLoginSucceeded();
      AuthService.clearRegisterFormDraft();

      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (r) => false);
    } catch (e) {
      if (!mounted) return;
      // Firebase kullanıcısı oluşturulduysa ama kayıt başarısız olduysa temizle
      try {
        await FirebaseAuth.instance.currentUser?.delete();
      } catch (_) {}
      setState(() {
        _busy = false;
        final msg = e.toString().toUpperCase();
        if (msg.contains('WRONG_CODE')) {
          _statusMessage = 'Incorrect code. Please try again.';
        } else if (msg.contains('NO_ACTIVE_CODE')) {
          _statusMessage = 'Code expired. Tap Resend to get a new one.';
        } else {
          _statusMessage = ErrorHandler.getUserFriendlyMessage(e);
        }
      });
    }
  }

  static const double _otpHeight = 52;

  Widget _buildOtpLayer() {
    return ListenableBuilder(
      listenable: Listenable.merge([_codeController, _codeFocus]),
      builder: (context, _) {
        final digits = _codeController.text.replaceAll(RegExp(r'\D'), '');
        final len = digits.length;
        final focused = _codeFocus.hasFocus;
        final activeIndex = focused ? len.clamp(0, 4) : -1;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(5, (i) {
            final ch = i < len ? digits[i] : '';
            final isActive = focused && activeIndex == i;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 5, right: i == 4 ? 0 : 5),
                child: Container(
                  height: _otpHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive ? AppColors.primary : AppColors.border,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    ch,
                    style: AppTextStyles.heading3.copyWith(
                      fontSize: 22,
                      letterSpacing: 0.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildOtpField() {
    return SizedBox(
      height: _otpHeight,
      child: TextField(
        controller: _codeController,
        focusNode: _codeFocus,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        onChanged: (_) => setState(() {}),
        style: const TextStyle(color: Colors.transparent, fontSize: 1),
        cursorColor: Colors.transparent,
        decoration: const InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.primary),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xLarge,
                  AppSpacing.small,
                  AppSpacing.xLarge,
                  AppSpacing.large,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(Icons.pin_outlined, size: 36, color: AppColors.primary),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Verify your email',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.heading1.copyWith(fontSize: 22, letterSpacing: -0.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.email,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'We sent a 5-digit code to this address. Enter it below to complete your registration.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySecondary.copyWith(fontSize: 13, height: 1.35),
                          ),
                          ValueListenableBuilder<int>(
                            valueListenable: _cooldownNotifier,
                            builder: (context, cd, _) {
                              if (cd <= 0) return const SizedBox(height: 20);
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 12),
                                  Text(
                                    'New code in ${_formatCountdown(cd)}',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              );
                            },
                          ),
                          Stack(
                            children: [
                              _buildOtpLayer(),
                              Positioned.fill(child: _buildOtpField()),
                            ],
                          ),
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                _statusMessage!,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error, height: 1.35),
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton(
                              onPressed: _busy ? null : _verifyAndRegister,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                    )
                                  : const Text('Verify & Create Account',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ValueListenableBuilder<int>(
                            valueListenable: _cooldownNotifier,
                            builder: (context, cd, _) {
                              return SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: OutlinedButton(
                                  onPressed: (_resendBusy || cd > 0) ? null : _resend,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(color: AppColors.border),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: _resendBusy
                                      ? const SizedBox(
                                          width: 20, height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                        )
                                      : const Text('Resend code',
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

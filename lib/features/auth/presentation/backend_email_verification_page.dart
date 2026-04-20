import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/exceptions.dart'
    show dioExceptionBodyContains, dioResponseDataAsSearchString;
import '../../../core/utils/session_helper.dart';
import '../../../routes/app_routes.dart';
import '../data/services/auth_service.dart';
import 'login_page.dart';

/// Backend `POST /api/auth/verify-email` ile 5 haneli kod doğrulama; başarıdan sonra `login` veya `getMe`.
class BackendEmailVerificationPage extends StatefulWidget {
  final String email;

  /// Başarıda `Navigator.pop(context, true)`.
  final bool popWithSuccessResult;

  /// Başarıda stack’i [AppRoutes.home] ile değiştir.
  final bool navigateHomeOnSuccess;

  /// Ayarlar: yalnızca profili yenile (`getMe`), `POST /login` yok.
  final bool refreshProfileOnlyOnContinue;

  /// Açılışta bir kez `resend-verification` (ör. girişten gelen, kod yoksa).
  /// `false`: kayıt az önce `register` ile kod gönderdiyse tekrar isteme (çift mail önlenir).
  final bool requestVerificationEmailOnOpen;

  const BackendEmailVerificationPage({
    super.key,
    required this.email,
    this.popWithSuccessResult = false,
    this.navigateHomeOnSuccess = true,
    this.refreshProfileOnlyOnContinue = false,
    this.requestVerificationEmailOnOpen = true,
  });

  @override
  State<BackendEmailVerificationPage> createState() =>
      _BackendEmailVerificationPageState();
}

class _BackendEmailVerificationPageState
    extends State<BackendEmailVerificationPage> {
  final _authService = AuthService();
  final _scrollController = ScrollController();
  final _digitKeys = List.generate(5, (_) => GlobalKey());

  late final List<TextEditingController> _digitControllers;
  late final List<FocusNode> _digitFocusNodes;

  bool _busy = false;
  bool _resendBusy = false;
  bool _bootstrapBusy = false;
  bool _initialSendScheduled = false;
  int _cooldown = 0;
  String? _statusMessage;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _digitControllers = List.generate(5, (_) => TextEditingController());
    _digitFocusNodes = List.generate(
      5,
      (i) => FocusNode(onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.backspace &&
                _digitControllers[i].text.isEmpty &&
                i > 0) {
              _digitFocusNodes[i - 1].requestFocus();
              _digitControllers[i - 1].clear();
              _scrollToField(i - 1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }),
    );

    if (widget.requestVerificationEmailOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestCodeOnOpen());
    } else {
      _cooldown = 60;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startCooldownTimer();
        _digitFocusNodes.first.requestFocus();
        _scrollToField(0);
      });
    }
  }

  void _scrollToField(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _digitKeys[index].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: Duration.zero,
        );
      }
    });
  }

  String _combinedCode() =>
      _digitControllers.map((c) => c.text.trim()).join();

  void _onDigitChanged(int index, String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      _fillDigitsFromString(digits);
      return;
    }
    if (raw.isEmpty) return;

    final ch = digits.isEmpty ? '' : digits[digits.length - 1];
    if (ch.isEmpty) return;

    _digitControllers[index].value = TextEditingValue(
      text: ch,
      selection: const TextSelection.collapsed(offset: 1),
    );

    if (index < 4) {
      _digitFocusNodes[index + 1].requestFocus();
    }
  }

  void _fillDigitsFromString(String digits) {
    final chars = digits.split('');
    for (var i = 0; i < 5; i++) {
      _digitControllers[i].text = i < chars.length ? chars[i] : '';
    }
    final focusIndex = digits.length >= 5 ? 4 : digits.length.clamp(0, 4);
    _digitFocusNodes[focusIndex].requestFocus();
    _scrollToField(focusIndex);
    setState(() {});
  }

  /// Sunucudan kod e-postası iste; hata olursa ekranda göster.
  Future<void> _requestCodeOnOpen() async {
    if (!mounted || _initialSendScheduled) return;
    _initialSendScheduled = true;
    setState(() {
      _bootstrapBusy = true;
      _statusMessage = null;
    });
    try {
      await _authService.syncFirebaseUserAndRefreshIdToken();
      await _authService.resendVerification();
      if (!mounted) return;
      setState(() {
        _bootstrapBusy = false;
        _cooldown = 60;
      });
      _startCooldownTimer();
      _digitFocusNodes.first.requestFocus();
      _scrollToField(0);
    } catch (e) {
      if (!mounted) return;
      final combined =
          '${e.toString()} ${e is DioException ? dioResponseDataAsSearchString(e.response?.data) : ''}'
              .toUpperCase();
      setState(() {
        _bootstrapBusy = false;
        if (combined.contains('COOLDOWN') ||
            combined.contains('429') ||
            combined.contains('TOO MANY')) {
          _statusMessage =
              'A code may already be on the way. Check inbox and spam, or wait and use Resend.';
        } else {
          _statusMessage = ErrorHandler.getUserFriendlyMessage(e);
        }
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _scrollController.dispose();
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _digitFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    if (_cooldown <= 0) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _resend() async {
    if (_resendBusy || _cooldown > 0) return;
    setState(() {
      _resendBusy = true;
      _statusMessage = null;
    });
    try {
      await _authService.resendVerification();
      if (!mounted) return;
      setState(() {
        _cooldown = 60;
        _resendBusy = false;
      });
      _startCooldownTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resendBusy = false;
        _statusMessage = ErrorHandler.getUserFriendlyMessage(e);
      });
    }
  }

  String _formatCountdown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// [verify-email] tamamlanana kadar başka ekrana geçiş yok.
  Future<void> _verifyAndContinue() async {
    setState(() => _statusMessage = null);
    final code = _combinedCode();
    if (code.length != 5 || !RegExp(r'^\d{5}$').hasMatch(code)) {
      setState(() {
        _statusMessage = 'Enter the full 5-digit code.';
      });
      return;
    }

    setState(() => _busy = true);
    try {
      await _authService.syncFirebaseUserAndRefreshIdToken();
      final verifiedUser = await _authService.verifyEmail(code);

      if (verifiedUser.emailVerified == false) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _statusMessage =
              'Verification did not complete. Check the code and try again.';
        });
        return;
      }

      if (widget.refreshProfileOnlyOnContinue) {
        try {
          await FirebaseAuth.instance.currentUser?.reload();
        } catch (_) {}
        await _authService.getMe();
        if (!mounted) return;
        setState(() => _busy = false);
        if (widget.popWithSuccessResult) {
          Navigator.pop(context, true);
        }
        return;
      }

      await _authService.establishBackendSession();
      SessionHelper().markBackendLoginSucceeded();
      if (!mounted) return;
      AuthService.clearRegisterFormDraft();
      setState(() => _busy = false);

      if (widget.popWithSuccessResult) {
        Navigator.pop(context, true);
      } else if (widget.navigateHomeOnSuccess) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.home,
          (r) => false,
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusMessage = dioExceptionBodyContains(e, 'EMAIL_NOT_VERIFIED')
            ? 'Enter the 5-digit code from your email, then tap Verify.'
            : ErrorHandler.getUserFriendlyMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusMessage = ErrorHandler.getUserFriendlyMessage(e);
      });
    }
  }

  Future<void> _signOut() async {
    SessionHelper().clearSession();
    AuthService.clearRegisterFormDraft();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Widget _otpField(int index) {
    return KeyedSubtree(
      key: _digitKeys[index],
      child: SizedBox(
        width: 52,
        child: TextFormField(
          controller: _digitControllers[index],
          focusNode: _digitFocusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          style: AppTextStyles.heading3.copyWith(
            fontSize: 22,
            letterSpacing: 0.5,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          onTap: () => _scrollToField(index),
          onChanged: (v) => _onDigitChanged(index, v),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: (_busy || _bootstrapBusy)
              ? null
              : () {
                  if (widget.popWithSuccessResult) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacementNamed(context, AppRoutes.login);
                  }
                },
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              padding: EdgeInsets.only(
                left: AppSpacing.xLarge,
                right: AppSpacing.xLarge,
                top: AppSpacing.small,
                bottom:
                    MediaQuery.of(context).viewInsets.bottom + AppSpacing.large,
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
                          child: Icon(
                            Icons.pin_outlined,
                            size: 36,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Verification code',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.heading1.copyWith(
                            fontSize: 22,
                            letterSpacing: -0.4,
                          ),
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
                          widget.requestVerificationEmailOnOpen
                              ? 'We email a 5-digit code to this address.'
                              : 'We just sent a 5-digit code to this address.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySecondary.copyWith(
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        if (_bootstrapBusy) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 6),
                          Text(
                            'Sending code…',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        if (_cooldown > 0 && !_bootstrapBusy) ...[
                          const SizedBox(height: 12),
                          Text(
                            'New code in ${_formatCountdown(_cooldown)}',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children:
                              List.generate(5, (i) => _otpField(i)),
                        ),
                        if (_statusMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              _statusMessage!,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.error,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            onPressed: _busy ? null : _verifyAndContinue,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  AppColors.primary.withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Verify',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: OutlinedButton(
                            onPressed: (_resendBusy || _cooldown > 0)
                                ? null
                                : _resend,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _resendBusy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : const Text(
                                    'Resend code',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _signOut,
                          child: Text(
                            'Sign out',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
    );
  }
}

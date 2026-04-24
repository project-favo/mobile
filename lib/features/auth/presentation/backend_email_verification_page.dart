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

  /// Tek alan: odak taşınmaz → iOS’ta klavye titremesi olmaz.
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();

  bool _busy = false;
  bool _resendBusy = false;
  bool _bootstrapBusy = false;
  bool _initialSendScheduled = false;
  final ValueNotifier<int> _cooldownNotifier = ValueNotifier(0);
  String? _statusMessage;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();

    if (widget.requestVerificationEmailOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestCodeOnOpen());
    } else {
      _cooldownNotifier.value = 60;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startCooldownTimer();
        _codeFocus.requestFocus();
      });
    }
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
        _cooldownNotifier.value = 60;
      });
      _startCooldownTimer();
      _codeFocus.requestFocus();
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
    _cooldownNotifier.dispose();
    _scrollController.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    if (_cooldownNotifier.value <= 0) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final v = _cooldownNotifier.value;
      if (v <= 1) {
        _cooldownNotifier.value = 0;
        t.cancel();
      } else {
        _cooldownNotifier.value = v - 1;
      }
    });
  }

  Future<void> _resend() async {
    if (_resendBusy || _cooldownNotifier.value > 0) return;
    setState(() {
      _resendBusy = true;
      _statusMessage = null;
    });
    try {
      await _authService.resendVerification();
      if (!mounted) return;
      setState(() {
        _resendBusy = false;
      });
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

  String _formatCountdown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _combinedCode() =>
      _codeController.text.replaceAll(RegExp(r'\D'), '').trim();

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

  static const double _otpHeight = 52;

  /// Görsel kutular (dokunma alttaki [TextField]’a gider); klavye tek odakta kalır.
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
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: TextField(
              controller: _codeController,
              focusNode: _codeFocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 5,
              showCursor: false,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                color: Colors.transparent,
                fontSize: 1,
                height: 1,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
                isDense: true,
                filled: false,
              ),
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.center,
              onTapOutside: (_) => _codeFocus.unfocus(),
            ),
          ),
          IgnorePointer(child: _buildOtpLayer()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
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
                        ValueListenableBuilder<int>(
                          valueListenable: _cooldownNotifier,
                          builder: (context, cd, _) {
                            if (cd <= 0 || _bootstrapBusy) {
                              return const SizedBox(height: 20);
                            }
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
                        _buildOtpField(),
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
                        ValueListenableBuilder<int>(
                          valueListenable: _cooldownNotifier,
                          builder: (context, cd, _) {
                            return SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: OutlinedButton(
                                onPressed:
                                    (_resendBusy || cd > 0) ? null : _resend,
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
    );
  }
}

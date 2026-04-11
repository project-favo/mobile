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
import '../../../core/widgets/app_input.dart';
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

  /// Açılışta bir kez `resend-verification` (kod mailinin gitmesi için).
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
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _resendBusy = false;
  bool _bootstrapBusy = false;
  bool _initialSendScheduled = false;
  int _cooldown = 0;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    if (widget.requestVerificationEmailOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestCodeOnOpen());
    }
  }

  /// Sunucudan kod e-postası iste; hata olursa ekranda göster (sessiz yutma yok).
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
      _tickCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verification code sent. Check inbox and spam / promotions.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final combined = '${e.toString()} ${e is DioException ? dioResponseDataAsSearchString(e.response?.data) : ''}'
          .toUpperCase();
      setState(() {
        _bootstrapBusy = false;
        if (combined.contains('COOLDOWN') ||
            combined.contains('429') ||
            combined.contains('TOO MANY')) {
          _statusMessage =
              'A code may already be on the way. Check inbox and spam. If you see nothing, wait 60 seconds and tap Resend code.';
        } else {
          _statusMessage = ErrorHandler.getUserFriendlyMessage(e);
        }
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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
      _tickCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A new code was sent. Check your inbox and spam folder.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resendBusy = false;
        _statusMessage = ErrorHandler.getUserFriendlyMessage(e);
      });
    }
  }

  void _tickCooldown() {
    if (_cooldown <= 0 || !mounted) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _cooldown--;
        if (_cooldown > 0) _tickCooldown();
      });
    });
  }

  String? _codeValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter the 5-digit code';
    if (!RegExp(r'^\d{5}$').hasMatch(s)) {
      return 'Code must be exactly 5 digits';
    }
    return null;
  }

  /// [verify-email] tamamlanana kadar başka ekrana geçiş yok.
  Future<void> _verifyAndContinue() async {
    setState(() {
      _statusMessage = null;
    });
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await _authService.syncFirebaseUserAndRefreshIdToken();
      final verifiedUser =
          await _authService.verifyEmail(_codeController.text.trim());

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
            ? 'Enter the 5-digit code from your Favo email, then tap Verify.'
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
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
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: AppSpacing.xLarge,
              right: AppSpacing.xLarge,
              top: AppSpacing.large,
              bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.large,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.pin_outlined,
                        size: 44,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Enter verification code',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.heading1.copyWith(
                        fontSize: 26,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We sent a 5-digit code to',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySecondary.copyWith(
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.email,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Enter the code below. Your account is confirmed on the server only after this step succeeds.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySecondary.copyWith(
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (_bootstrapBusy) ...[
                      const SizedBox(height: 20),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        'Requesting verification code from server…',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    AppInput(
                      controller: _codeController,
                      hint: '5-digit code',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      validator: _codeValidator,
                    ),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
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
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed:
                            (_resendBusy || _cooldown > 0) ? null : _resend,
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
                            : Text(
                                _cooldown > 0
                                    ? 'Resend code ($_cooldown s)'
                                    : 'Resend code',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
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
        ),
      ),
    );
  }
}

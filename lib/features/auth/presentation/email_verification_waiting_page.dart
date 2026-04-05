import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/exceptions.dart' show dioExceptionBodyContains;
import '../../../core/utils/session_helper.dart';
import '../../../routes/app_routes.dart';
import '../data/services/auth_service.dart';
import 'login_page.dart';

/// Email-only verification UX (no PIN). English, layout suited for onboarding.
class EmailVerificationWaitingPage extends StatefulWidget {
  final String email;

  /// After success, `Navigator.pop(context, true)` instead of going home.
  final bool popWithSuccessResult;

  /// After success, replace stack with [AppRoutes.home].
  final bool navigateHomeOnSuccess;

  /// Settings: only refresh profile via [AuthService.getMe] (no POST /login).
  final bool refreshProfileOnlyOnContinue;

  const EmailVerificationWaitingPage({
    super.key,
    required this.email,
    this.popWithSuccessResult = false,
    this.navigateHomeOnSuccess = true,
    this.refreshProfileOnlyOnContinue = false,
  });

  @override
  State<EmailVerificationWaitingPage> createState() =>
      _EmailVerificationWaitingPageState();
}

class _EmailVerificationWaitingPageState
    extends State<EmailVerificationWaitingPage> {
  final _authService = AuthService();
  bool _busy = false;
  bool _resendBusy = false;
  int _cooldown = 0;
  String? _statusMessage;

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
            'Verification email sent. Please check your inbox and spam folder.',
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

  Future<void> _continuePressed() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      if (widget.refreshProfileOnlyOnContinue) {
        try {
          await FirebaseAuth.instance.currentUser?.reload();
        } catch (_) {}
        final me = await _authService.getMe();
        if (!mounted) return;
        if (me.isEmailVerified) {
          if (widget.popWithSuccessResult) {
            Navigator.pop(context, true);
          }
          return;
        }
        setState(() {
          _busy = false;
          _statusMessage =
              'Your email is not verified yet. Open the link we sent, then tap Continue again.';
        });
        return;
      }

      await _authService.syncFirebaseUserAndRefreshIdToken();
      await _authService.establishBackendSession();
      SessionHelper().markBackendLoginSucceeded();
      if (!mounted) return;
      AuthService.clearRegisterFormDraft();
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
      if (dioExceptionBodyContains(e, 'EMAIL_NOT_VERIFIED')) {
        setState(() {
          _busy = false;
          _statusMessage =
              'Your email is not verified yet. Check your inbox, confirm the message, then tap Continue again.';
        });
        return;
      }
      setState(() {
        _busy = false;
        _statusMessage = ErrorHandler.getUserFriendlyMessage(e);
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
          onPressed: _busy
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xLarge,
              vertical: AppSpacing.large,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const SizedBox(height: 8),
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
                      Icons.mark_email_read_outlined,
                      size: 44,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Verify your email',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heading1.copyWith(
                      fontSize: 26,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a verification message to',
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
                    'Open the link in that email to confirm your address. '
                    'If it does not appear within a few minutes, check your spam or promotions folder.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySecondary.copyWith(
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 24),
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
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _continuePressed,
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
                              'Continue',
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
                      onPressed: (_resendBusy || _cooldown > 0) ? null : _resend,
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
                                  ? 'Resend email ($_cooldown s)'
                                  : 'Resend verification email',
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
    );
  }
}

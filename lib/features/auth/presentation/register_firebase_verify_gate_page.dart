import 'dart:async';

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
import '../data/models/register_request_dto.dart';
import '../data/services/auth_service.dart';
import 'email_verification_waiting_page.dart';
import 'login_page.dart';

/// Step 1 of sign-up: confirm email via Firebase link, then create the app profile on the server.
class RegisterFirebaseVerifyGatePage extends StatefulWidget {
  final String email;
  final RegisterRequestDto pendingRegistration;

  const RegisterFirebaseVerifyGatePage({
    super.key,
    required this.email,
    required this.pendingRegistration,
  });

  @override
  State<RegisterFirebaseVerifyGatePage> createState() =>
      _RegisterFirebaseVerifyGatePageState();
}

class _RegisterFirebaseVerifyGatePageState
    extends State<RegisterFirebaseVerifyGatePage> with WidgetsBindingObserver {
  final _authService = AuthService();
  bool _busy = false;
  bool _resending = false;
  int _cooldown = 0;
  String? _error;
  bool _firebaseVerifiedHint = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _refreshFirebaseVerified());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshFirebaseVerified(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFirebaseVerified();
    }
  }

  Future<void> _refreshFirebaseVerified() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await u.reload();
    } catch (_) {}
    final v = FirebaseAuth.instance.currentUser?.emailVerified == true;
    if (!mounted) return;
    if (v != _firebaseVerifiedHint) {
      setState(() => _firebaseVerifiedHint = v);
    }
  }

  Future<void> _completeRegistrationOnServer() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _authService.syncFirebaseUserAndRefreshIdToken();
      await _authService.registerOnBackend(
        widget.pendingRegistration,
        requireFirebaseEmailVerified: true,
      );
      if (!mounted) return;
      try {
        await _authService.resendVerification();
      } catch (_) {}

      try {
        await _authService.establishBackendSession();
        SessionHelper().markBackendLoginSucceeded();
        if (!mounted) return;
        AuthService.clearRegisterFormDraft();
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.home,
          (_) => false,
        );
        return;
      } on DioException catch (e) {
        if (!dioExceptionBodyContains(e, 'EMAIL_NOT_VERIFIED')) {
          if (!mounted) return;
          setState(() {
            _error = ErrorHandler.getUserFriendlyMessage(e);
            _busy = false;
          });
          return;
        }
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmailVerificationWaitingPage(
            email: widget.email,
            navigateHomeOnSuccess: true,
            popWithSuccessResult: false,
            refreshProfileOnlyOnContinue: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getUserFriendlyMessage(e);
        _busy = false;
      });
    }
  }

  Future<void> _resendFirebase() async {
    if (_resending || _cooldown > 0) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await _authService.resendFirebaseEmailVerification();
      if (!mounted) return;
      setState(() {
        _cooldown = 60;
        _resending = false;
      });
      _tickCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verification email sent. Check your inbox and spam folder.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getUserFriendlyMessage(e);
        _resending = false;
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

  Future<void> _signOutAndLeave() async {
    AuthService.clearRegisterFormDraft();
    SessionHelper().clearSession();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Future<void> _confirmCancel() async {
    if (_busy) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Cancel sign-up?',
          style: AppTextStyles.heading3.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'Your progress will be lost and you will be signed out. You can register again with the same email.',
          style: AppTextStyles.bodySecondary.copyWith(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Stay',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sign out',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) await _signOutAndLeave();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
            tooltip: 'Close',
            onPressed: _busy ? null : _confirmCancel,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xLarge,
                vertical: AppSpacing.medium,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
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
                        Icons.outgoing_mail,
                        size: 44,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Confirm your email',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.heading1.copyWith(
                        fontSize: 26,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We sent a link to',
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
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Tap the link in that email, then return to this screen. '
                      'When your address is verified, the button below will unlock.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySecondary.copyWith(
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (_firebaseVerifiedHint) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: AppColors.success, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Email confirmed — you can finish creating your account.',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
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
                          _error!,
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
                        onPressed: _busy || !_firebaseVerifiedHint
                            ? null
                            : _completeRegistrationOnServer,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha: 0.45),
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
                        onPressed: (_resending || _cooldown > 0)
                            ? null
                            : _resendFirebase,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _resending
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
                                    : 'Resend email',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : _signOutAndLeave,
                      child: Text(
                        'I already have an account — Sign in',
                        style: AppTextStyles.bodySmall.copyWith(
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

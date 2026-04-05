import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../routes/app_routes.dart';
import '../../../../core/utils/session_helper.dart';
import '../data/services/auth_service.dart';

class EmailVerificationPage extends StatefulWidget {
  final String email;

  /// Ayarlardan opsiyonel doğrulama: doğrulama sonrası `POST /login` çağrılmaz.
  final bool onlyVerifyNoBackendLogin;

  /// `true`: doğrulama (+ gerekirse login) sonrası `Navigator.pop(context, true)`.
  final bool popOnSuccessWithResult;

  const EmailVerificationPage({
    super.key,
    required this.email,
    this.onlyVerifyNoBackendLogin = false,
    this.popOnSuccessWithResult = false,
  });

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final AuthService _authService = AuthService();
  final _codeController = TextEditingController();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // İlk açılışta otomatik resend yapma; kullanıcı register akışından geldi,
    // backend zaten kod göndermiş olabilir.
  }

  @override
  void dispose() {
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown = 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _isResending) return;
    setState(() { _isResending = true; _errorMessage = null; });
    try {
      await _authService.resendVerification();
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Doğrulama kodu gönderildi.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg == 'RESEND_COOLDOWN') {
        _startCooldown();
        setState(() => _errorMessage = 'Lütfen 60 saniye bekleyin.');
      } else if (msg == 'ALREADY_VERIFIED') {
        if (widget.onlyVerifyNoBackendLogin) {
          if (mounted) Navigator.pop(context, true);
        } else {
          await SessionHelper().refreshSession();
          if (!mounted) return;
          if (widget.popOnSuccessWithResult) {
            Navigator.pop(context, true);
          } else {
            AuthService.clearRegisterFormDraft();
            Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.home,
              (r) => false,
            );
          }
        }
      } else {
        setState(() => _errorMessage = msg);
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 5) {
      setState(() => _errorMessage = 'Lütfen 5 haneli kodu girin.');
      return;
    }
    setState(() { _isVerifying = true; _errorMessage = null; });
    try {
      await _authService.verifyEmail(code);
      if (widget.onlyVerifyNoBackendLogin) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      await SessionHelper().refreshSession();
      if (!mounted) return;
      if (widget.popOnSuccessWithResult) {
        Navigator.pop(context, true);
      } else {
        AuthService.clearRegisterFormDraft();
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (r) => false);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = _friendlyError(msg);
        _isVerifying = false;
      });
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'WRONG_CODE': return 'Kod hatalı, lütfen tekrar deneyin.';
      case 'NO_ACTIVE_CODE': return 'Aktif kod bulunamadı. Yeni kod gönderin.';
      case 'INVALID_CODE_FORMAT': return 'Kod 5 haneli sayı olmalıdır.';
      case 'USER_NOT_FOUND': return 'Kullanıcı bulunamadı.';
      default: return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.popOnSuccessWithResult ||
                widget.onlyVerifyNoBackendLogin) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, AppRoutes.login);
            }
          },
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mark_email_read_outlined,
                      size: 40, color: AppColors.primary),
                ),
                const SizedBox(height: AppSpacing.xLarge),
                const Text('E-postanı Doğrula', style: AppTextStyles.heading2),
                const SizedBox(height: AppSpacing.medium),
                Text(
                  '${widget.email} adresine 5 haneli doğrulama kodu gönderdik.',
                  style: AppTextStyles.bodySecondary,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxLarge),

                // ── Kod girişi ──────────────────────────────────────
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 12,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '_ _ _ _ _',
                    hintStyle: TextStyle(
                      fontSize: 28,
                      letterSpacing: 12,
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    errorText: _errorMessage,
                  ),
                  onChanged: (_) {
                    if (_errorMessage != null) setState(() => _errorMessage = null);
                  },
                ),

                const SizedBox(height: AppSpacing.xLarge),

                AppButton(
                  text: 'Doğrula',
                  isLoading: _isVerifying,
                  onPressed: _verify,
                ),

                const SizedBox(height: AppSpacing.large),

                // ── Yeniden gönder ──────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Kod gelmedi mi? ', style: AppTextStyles.bodySecondary),
                    GestureDetector(
                      onTap: _cooldown > 0 || _isResending ? null : _resend,
                      child: _isResending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : Text(
                              _cooldown > 0
                                  ? 'Tekrar gönder ($_cooldown s)'
                                  : 'Tekrar gönder',
                              style: AppTextStyles.link.copyWith(
                                color: _cooldown > 0
                                    ? AppColors.textSecondary
                                    : AppColors.primary,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

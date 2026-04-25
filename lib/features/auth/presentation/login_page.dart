import 'package:flutter/material.dart';
import '../../../routes/app_routes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_input.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/exceptions.dart';
import 'backend_email_verification_page.dart';
import 'forgot_password_page.dart';
import '../data/services/auth_service.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _emailFieldKey = GlobalKey();
  final _passwordFieldKey = GlobalKey();

  bool _obscure = true;
  bool _submitted = false;
  bool _isLoading = false;
  String? _authError; // Backend'den gelen authentication error

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _scrollFieldIntoView(GlobalKey fieldKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = fieldKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.22,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String? _emailValidator(String? v) {
    // Önce backend error'u kontrol et (yanlış email/şifre gibi)
    // Email field'ında çerçeve kırmızı olsun ama mesaj password field'ında gösterilsin
    if (_authError != null) {
      // Sadece çerçeveyi kırmızı yapmak için boş string döndürme, 
      // bunun yerine null döndürüp error state'i başka şekilde yönetmeliyiz
      // Ya da aynı mesajı gösterelim
      return _authError;
    }
    
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Email is required";
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
    if (!ok) return "Enter a valid email";
    return null;
  }

  String? _passwordValidator(String? v) {
    // Önce backend error'u kontrol et (yanlış şifre gibi)
    if (_authError != null) {
      return _authError;
    }
    
    final value = (v ?? '');
    if (value.isEmpty) return "Password is required";
    if (value.length < 6) return "Min 6 characters";
    return null;
  }

  Future<void> _onLogin() async {
    // Önceki error'u temizle
    setState(() {
      _authError = null;
      _submitted = true;
    });
    
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _isLoading = true);

    try {
      await _authService.loginWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      AuthService.clearRegisterFormDraft();

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } on EmailNotVerifiedException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BackendEmailVerificationPage(
              email: e.email,
              navigateHomeOnSuccess: true,
              popWithSuccessResult: false,
              refreshProfileOnlyOnContinue: false,
            ),
          ),
        );
      }
    } on IncompleteBackendRegistrationException catch (_) {
      if (mounted) {
        setState(() {
          _authError = ErrorHandler.getUserFriendlyMessage(
            const IncompleteBackendRegistrationException(),
          );
          _isLoading = false;
        });
        _formKey.currentState?.validate();
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        setState(() {
          _authError = errorMessage;
          _isLoading = false;
        });
        _formKey.currentState?.validate();
      }
    } finally {
      if (mounted && _authError == null) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ForgotPasswordPage(
          initialEmail: _email.text.trim(),
        ),
      ),
    );
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.background,

    body: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(), // klavye kapat
      child: SafeArea(
        child: Stack(
          children: [

            SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ÜST GÖRSEL (ARTIK SCROLL EDİYOR)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Transform.translate(
                      offset: const Offset(-40, -30),
                      child: Transform.rotate(
                        angle: -1,
                        child: Image.asset(
                          "assets/images/login_illustration.jpg",
                          width: 380,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // FORM ALANI
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _submitted
                          ? AutovalidateMode.always
                          : AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Welcome",
                            style: AppTextStyles.heading1,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Sign in to continue your journey",
                            style: AppTextStyles.bodySecondary.copyWith(
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 18),

                          KeyedSubtree(
                            key: _emailFieldKey,
                            child: AppInput(
                              controller: _email,
                              focusNode: _emailFocus,
                              hint: "Email Address",
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) {
                                _passwordFocus.requestFocus();
                                _scrollFieldIntoView(_passwordFieldKey);
                              },
                              validator: _emailValidator,
                              onChanged: () {
                                if (_authError != null) {
                                  setState(() => _authError = null);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 14),

                          KeyedSubtree(
                            key: _passwordFieldKey,
                            child: AppInput(
                              controller: _password,
                              focusNode: _passwordFocus,
                              hint: "Password",
                              obscure: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _onLogin(),
                              onToggleObscure: () =>
                                  setState(() => _obscure = !_obscure),
                              validator: _passwordValidator,
                              onChanged: () {
                                if (_authError != null) {
                                  setState(() => _authError = null);
                                }
                              },
                            ),
                          ),

                          const SizedBox(height: 6),

                          GestureDetector(
                            onTap: _onForgotPassword,
                            child: const Text(
                              "Forgot password?",
                              style: AppTextStyles.link,
                            ),
                          ),

                          const SizedBox(height: 20),

                          AppButton(
                            text: "Login",
                            isLoading: _isLoading,
                            onPressed: _onLogin,
                          ),

                          const SizedBox(height: 14),

                          Center(
                            child: RichText(
                              text: TextSpan(
                                style: AppTextStyles.bodySecondary,
                                children: [
                                  const TextSpan(text: "Not a member? "),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () => Navigator.pushNamed(
                                          context, AppRoutes.register),
                                      child: const Text(
                                        "Register now",
                                        style: AppTextStyles.link,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),
                          const Divider(height: 1, color: AppColors.border),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}



}
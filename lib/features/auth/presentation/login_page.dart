import 'package:flutter/material.dart';
import '../../../routes/app_routes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_input.dart';
import '../../../core/theme/app_colors.dart';
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

  bool _obscure = true;
  bool _submitted = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _emailValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Email is required";
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
    if (!ok) return "Enter a valid email";
    return null;
  }

  String? _passwordValidator(String? v) {
    final value = (v ?? '');
    if (value.isEmpty) return "Password is required";
    if (value.length < 6) return "Min 6 characters";
    return null;
  }

  Future<void> _onLogin() async {
    setState(() => _submitted = true);
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _isLoading = true);

    try {
      // Firebase Auth ile giriş yap ve backend'e istek gönder
      final userDto = await _authService.loginWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      // Başarılı giriş - TODO: Home sayfasına yönlendir veya state management ile user'ı sakla
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Welcome ${userDto.userName}!',
              style: AppTextStyles.body,
            ),
            backgroundColor: AppColors.success,
          ),
        );
        // Navigator.pushReplacementNamed(context, AppRoutes.home); // Home route'u eklendiğinde
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Wrong e-mail or password!',
              style: AppTextStyles.body,
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onForgotPassword() {
    // TODO: Forgot password ekranı/aksiyonu eklenebilir
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Forgot password clicked")),
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
                            "Welcome!",
                            style: AppTextStyles.heading1,
                          ),
                          const SizedBox(height: 18),

                          AppInput(
                            controller: _email,
                            hint: "Email Address",
                            keyboardType: TextInputType.emailAddress,
                            validator: _emailValidator,
                          ),
                          const SizedBox(height: 10),

                          AppInput(
                            controller: _password,
                            hint: "Password",
                            obscure: _obscure,
                            onToggleObscure: () =>
                                setState(() => _obscure = !_obscure),
                            validator: _passwordValidator,
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
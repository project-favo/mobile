import 'package:flutter/material.dart';
import '../../../routes/app_routes.dart';
import 'widgets/input_field.dart';
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
            content: Text('Welcome ${userDto.userName}!'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigator.pushReplacementNamed(context, AppRoutes.home); // Home route'u eklendiğinde
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
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
    backgroundColor: const Color(0xFFECF4F7),

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
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF39404B),
                            ),
                          ),
                          const SizedBox(height: 18),

                          InputField(
                            controller: _email,
                            hint: "Email Address",
                            keyboardType: TextInputType.emailAddress,
                            validator: _emailValidator,
                          ),
                          const SizedBox(height: 10),

                          InputField(
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
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF910029),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _onLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF910029),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Color(0xFFF8F9FE),
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      "Login",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFF8F9FE),
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          Center(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF71727A),
                                ),
                                children: [
                                  const TextSpan(text: "Not a member? "),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () => Navigator.pushNamed(
                                          context, AppRoutes.register),
                                      child: const Text(
                                        "Register now",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF910029),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),
                          const Divider(height: 1, color: Color(0xFFD4D6DD)),
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
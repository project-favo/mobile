import 'package:flutter/material.dart';
import '../../../routes/app_routes.dart';
import 'widgets/input_field.dart';
import '../data/services/auth_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _userName = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _submitted = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _userName.dispose();
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

  String? _confirmPasswordValidator(String? v) {
    if (v != _password.text) return "Passwords do not match";
    return null;
  }

  String? _userNameValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Username is required";
    if (value.length < 3) return "Min 3 characters";
    return null;
  }

  Future<void> _onRegister() async {
    setState(() => _submitted = true);
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _isLoading = true);

    try {
      // Firebase Auth ile kayıt ol ve backend'e istek gönder
      final userDto = await _authService.registerWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
        userName: _userName.text.trim(),
      );

      // Başarılı kayıt - Login sayfasına yönlendir
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration successful! Welcome ${userDto.userName}!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushReplacementNamed(context, AppRoutes.login);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECF4F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF39404B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Form(
              key: _formKey,
              autovalidateMode: _submitted
                  ? AutovalidateMode.always
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    "Create Account",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF39404B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Sign up to get started",
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF71727A),
                    ),
                  ),
                  const SizedBox(height: 32),

                  InputField(
                    controller: _userName,
                    hint: "Username",
                    validator: _userNameValidator,
                  ),
                  const SizedBox(height: 10),

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
                    obscure: _obscurePassword,
                    onToggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    validator: _passwordValidator,
                  ),
                  const SizedBox(height: 10),

                  InputField(
                    controller: _confirmPassword,
                    hint: "Confirm Password",
                    obscure: _obscureConfirmPassword,
                    onToggleObscure: () => setState(
                        () => _obscureConfirmPassword = !_obscureConfirmPassword),
                    validator: _confirmPasswordValidator,
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _onRegister,
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
                              "Register",
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
                          const TextSpan(text: "Already have an account? "),
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: () => Navigator.pushReplacementNamed(
                                  context, AppRoutes.login),
                              child: const Text(
                                "Login now",
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

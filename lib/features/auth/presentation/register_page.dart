import 'package:flutter/material.dart';
import '../../../routes/app_routes.dart';
import '../../../core/widgets/app_input.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_colors.dart';
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
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _birthdate = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _submitted = false;
  bool _isLoading = false;
  DateTime? _selectedDate;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _userName.dispose();
    _name.dispose();
    _surname.dispose();
    _birthdate.dispose();
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

  String? _nameValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Name is required";
    return null;
  }

  String? _surnameValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Surname is required";
    return null;
  }

  String? _birthdateValidator(String? v) {
    if (_selectedDate == null) return "Birthdate is required";
    return null;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _birthdate.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
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
        name: _name.text.trim(),
        surname: _surname.text.trim(),
        birthdate: _birthdate.text.trim(),
      );

      // Başarılı kayıt - Login sayfasına yönlendir
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Registration successful! Welcome ${userDto.userName}!',
              style: AppTextStyles.body,
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
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
                    style: AppTextStyles.heading1,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Sign up to get started",
                    style: AppTextStyles.bodySecondary,
                  ),
                  const SizedBox(height: 32),

                  AppInput(
                    controller: _userName,
                    hint: "Username",
                    validator: _userNameValidator,
                  ),
                  const SizedBox(height: 10),

                  AppInput(
                    controller: _name,
                    hint: "Name",
                    validator: _nameValidator,
                  ),
                  const SizedBox(height: 10),

                  AppInput(
                    controller: _surname,
                    hint: "Surname",
                    validator: _surnameValidator,
                  ),
                  const SizedBox(height: 10),

                  GestureDetector(
                    onTap: () => _selectDate(context),
                    child: AbsorbPointer(
                      child: AppInput(
                        controller: _birthdate,
                        hint: "Birthdate",
                        validator: _birthdateValidator,
                        suffixIcon: const Icon(Icons.calendar_today, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

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
                    obscure: _obscurePassword,
                    onToggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    validator: _passwordValidator,
                  ),
                  const SizedBox(height: 10),

                  AppInput(
                    controller: _confirmPassword,
                    hint: "Confirm Password",
                    obscure: _obscureConfirmPassword,
                    onToggleObscure: () => setState(
                        () => _obscureConfirmPassword = !_obscureConfirmPassword),
                    validator: _confirmPasswordValidator,
                  ),

                  const SizedBox(height: 24),

                  AppButton(
                    text: "Register",
                    isLoading: _isLoading,
                    onPressed: _onRegister,
                  ),

                  const SizedBox(height: 14),

                  Center(
                    child: RichText(
                      text: TextSpan(
                        style: AppTextStyles.bodySecondary,
                        children: [
                          const TextSpan(text: "Already have an account? "),
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: () => Navigator.pushReplacementNamed(
                                  context, AppRoutes.login),
                              child: const Text(
                                "Login now",
                                style: AppTextStyles.link,
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

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../routes/app_routes.dart';
import '../../../core/widgets/app_input.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_handler.dart';
import '../data/services/auth_service.dart';
import '../data/models/register_request_dto.dart';
import 'email_verification_page.dart';

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
  bool _acknowledgedEmailVerification = false;
  DateTime? _selectedDate;
  String? _registerError; // Backend'den gelen registration error
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedProfilePhoto;

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
    // Önce backend error'u kontrol et (email zaten kayıtlı gibi)
    if (_registerError != null && _registerError!.toLowerCase().contains('email')) {
      return _registerError;
    }
    
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
    // Önce backend error'u kontrol et (username zaten alınmış gibi)
    if (_registerError != null && _registerError!.toLowerCase().contains('username')) {
      return _registerError;
    }
    
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

  Future<void> _pickProfilePhoto(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (image != null) {
        setState(() {
          _selectedProfilePhoto = image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showPhotoSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickProfilePhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickProfilePhoto(ImageSource.camera);
              },
            ),
            if (_selectedProfilePhoto != null)
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('Remove Photo'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedProfilePhoto = null;
                  });
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _convertImageToBase64() async {
    if (_selectedProfilePhoto == null) return null;
    
    try {
      final file = File(_selectedProfilePhoto!.path);
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final mimeType = _selectedProfilePhoto!.mimeType ?? 'image/jpeg';
      // Data URI formatında döndür: "data:image/jpeg;base64,..."
      return 'data:$mimeType;base64,$base64String';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process image: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return null;
    }
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
    // Önceki error'u temizle
    setState(() {
      _registerError = null;
      _submitted = true;
    });
    
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (!_acknowledgedEmailVerification) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please confirm you will enter the 5-digit code sent to your email.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Profil fotoğrafını base64'e çevir
      String? profilePhotoBase64;
      String? profilePhotoMimeType;
      
      if (_selectedProfilePhoto != null) {
        profilePhotoBase64 = await _convertImageToBase64();
        profilePhotoMimeType = _selectedProfilePhoto!.mimeType ?? 'image/jpeg';
      }

      final registerRequest = RegisterRequestDto(
        userName: _userName.text.trim(),
        name: _name.text.trim(),
        surname: _surname.text.trim(),
        birthdate: _birthdate.text.trim(),
        profilePhotoBase64: profilePhotoBase64,
        profilePhotoMimeType: profilePhotoMimeType,
      );
      AuthService.saveRegisterFormDraft(registerRequest);

      await _authService.signUpWithEmailPasswordAndBackend(
        email: _email.text.trim(),
        password: _password.text,
        request: registerRequest,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmailVerificationPage(
            email: _email.text.trim(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        // Backend error'u ilgili field'a set et
        setState(() {
          _registerError = errorMessage;
          _isLoading = false;
        });
        // Form'u yeniden validate et ki error gösterilsin
        _formKey.currentState?.validate();
      }
    } finally {
      if (mounted && _registerError == null) {
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

                  // Profile Photo Section
                  Center(
                    child: GestureDetector(
                      onTap: _showPhotoSourceDialog,
                      child: Stack(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.border,
                                width: 2,
                              ),
                              color: AppColors.surface,
                            ),
                            child: _selectedProfilePhoto != null
                                ? ClipOval(
                                    child: Image.file(
                                      File(_selectedProfilePhoto!.path),
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_outline_rounded,
                                    size: 60,
                                    color: AppColors.primary,
                                  ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.surface,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _selectedProfilePhoto != null
                          ? 'Tap to change photo'
                          : 'Tap to add profile photo (optional)',
                      style: AppTextStyles.bodySecondary.copyWith(
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  AppInput(
                    controller: _userName,
                    hint: "Username",
                    validator: _userNameValidator,
                    onChanged: () {
                      if (_registerError != null) {
                        setState(() => _registerError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  AppInput(
                    controller: _name,
                    hint: "Name",
                    validator: _nameValidator,
                  ),
                  const SizedBox(height: 14),

                  AppInput(
                    controller: _surname,
                    hint: "Surname",
                    validator: _surnameValidator,
                  ),
                  const SizedBox(height: 14),

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
                  const SizedBox(height: 14),

                  AppInput(
                    controller: _email,
                    hint: "Email Address",
                    keyboardType: TextInputType.emailAddress,
                    validator: _emailValidator,
                    onChanged: () {
                      if (_registerError != null) {
                        setState(() => _registerError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  AppInput(
                    controller: _password,
                    hint: "Password",
                    obscure: _obscurePassword,
                    onToggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    validator: _passwordValidator,
                  ),
                  const SizedBox(height: 14),

                  AppInput(
                    controller: _confirmPassword,
                    hint: "Confirm Password",
                    obscure: _obscureConfirmPassword,
                    onToggleObscure: () => setState(
                        () => _obscureConfirmPassword = !_obscureConfirmPassword),
                    validator: _confirmPasswordValidator,
                  ),

                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _acknowledgedEmailVerification,
                            activeColor: AppColors.primary,
                            onChanged: (v) {
                              setState(() {
                                _acknowledgedEmailVerification = v ?? false;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _acknowledgedEmailVerification =
                                  !_acknowledgedEmailVerification;
                            });
                          },
                          child: Text(
                            'I understand I must enter the 5-digit verification code '
                            'sent to my email before my account is fully active.',
                            style: AppTextStyles.bodySecondary.copyWith(
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ],
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
                              onTap: () => Navigator.pushNamed(
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

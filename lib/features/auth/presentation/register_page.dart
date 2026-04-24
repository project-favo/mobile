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
import '../../../core/utils/username_input_rules.dart';
import '../data/services/auth_service.dart';
import '../data/models/register_request_dto.dart';
import 'register_firebase_verify_gate_page.dart';

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

  final _userNameFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _surnameFocus = FocusNode();
  final _birthdateFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  final _userNameFieldKey = GlobalKey();
  final _nameFieldKey = GlobalKey();
  final _surnameFieldKey = GlobalKey();
  final _birthdateFieldKey = GlobalKey();
  final _emailFieldKey = GlobalKey();
  final _passwordFieldKey = GlobalKey();
  final _confirmPasswordFieldKey = GlobalKey();

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
  void initState() {
    super.initState();
    final map = <FocusNode, GlobalKey>{
      _userNameFocus: _userNameFieldKey,
      _nameFocus: _nameFieldKey,
      _surnameFocus: _surnameFieldKey,
      _birthdateFocus: _birthdateFieldKey,
      _emailFocus: _emailFieldKey,
      _passwordFocus: _passwordFieldKey,
      _confirmPasswordFocus: _confirmPasswordFieldKey,
    };
    map.forEach((focus, key) {
      focus.addListener(() {
        if (focus.hasFocus) _scrollFieldIntoView(key);
      });
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _userName.dispose();
    _name.dispose();
    _surname.dispose();
    _birthdate.dispose();
    _userNameFocus.dispose();
    _nameFocus.dispose();
    _surnameFocus.dispose();
    _birthdateFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  void _scrollFieldIntoView(GlobalKey fieldKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = fieldKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.2,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
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
    if (_registerError != null && _registerError!.toLowerCase().contains('username')) {
      return _registerError;
    }
    return UsernameInputRules.validateForForm(v);
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
              'Please confirm you will enter the 5-digit code Favo sends to your email.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Firebase'e istek atmadan önce kullanıcı adı müsaitliğini kontrol et
      final usernameAvailable = await _authService.checkUsernameAvailable(_userName.text.trim());
      if (!usernameAvailable) {
        if (mounted) {
          setState(() {
            _registerError = 'This username is already taken. Please choose another.';
            _isLoading = false;
          });
          _formKey.currentState?.validate();
        }
        return;
      }

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

      await _authService.createFirebaseUserForRegistration(
        email: _email.text.trim(),
        password: _password.text,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RegisterFirebaseVerifyGatePage(
            email: _email.text.trim(),
            pendingRegistration: registerRequest,
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FocusManager.instance.primaryFocus?.unfocus();
          });
        }
      },
      child: Scaffold(
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
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

                  KeyedSubtree(
                    key: _userNameFieldKey,
                    child: AppInput(
                      controller: _userName,
                      focusNode: _userNameFocus,
                      hint: "Username",
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        _nameFocus.requestFocus();
                        _scrollFieldIntoView(_nameFieldKey);
                      },
                      validator: _userNameValidator,
                      onChanged: () {
                        if (_registerError != null) {
                          setState(() => _registerError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  KeyedSubtree(
                    key: _nameFieldKey,
                    child: AppInput(
                      controller: _name,
                      focusNode: _nameFocus,
                      hint: "Name",
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        _surnameFocus.requestFocus();
                        _scrollFieldIntoView(_surnameFieldKey);
                      },
                      validator: _nameValidator,
                    ),
                  ),
                  const SizedBox(height: 14),

                  KeyedSubtree(
                    key: _surnameFieldKey,
                    child: AppInput(
                      controller: _surname,
                      focusNode: _surnameFocus,
                      hint: "Surname",
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        _birthdateFocus.requestFocus();
                        _scrollFieldIntoView(_birthdateFieldKey);
                      },
                      validator: _surnameValidator,
                    ),
                  ),
                  const SizedBox(height: 14),

                  KeyedSubtree(
                    key: _birthdateFieldKey,
                    child: GestureDetector(
                      onTap: () => _selectDate(context),
                      child: AbsorbPointer(
                        child: AppInput(
                          controller: _birthdate,
                          focusNode: _birthdateFocus,
                          hint: "Birthdate",
                          readOnly: true,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) {
                            _emailFocus.requestFocus();
                            _scrollFieldIntoView(_emailFieldKey);
                          },
                          validator: _birthdateValidator,
                          suffixIcon: const Icon(Icons.calendar_today,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

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
                        if (_registerError != null) {
                          setState(() => _registerError = null);
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
                      obscure: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        _confirmPasswordFocus.requestFocus();
                        _scrollFieldIntoView(_confirmPasswordFieldKey);
                      },
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      validator: _passwordValidator,
                    ),
                  ),
                  const SizedBox(height: 14),

                  KeyedSubtree(
                    key: _confirmPasswordFieldKey,
                    child: AppInput(
                      controller: _confirmPassword,
                      focusNode: _confirmPasswordFocus,
                      hint: "Confirm Password",
                      obscure: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _onRegister(),
                      onToggleObscure: () => setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword),
                      validator: _confirmPasswordValidator,
                    ),
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
                            'I understand Favo will send a 5-digit code to my email and I will '
                            'enter it to finish sign-up.',
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
                                      onTap: () {
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        Navigator.pushNamed(
                                          context,
                                          AppRoutes.login,
                                        );
                                      },
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
    ),
    );
  }
}

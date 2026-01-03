import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_input.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../auth/data/services/auth_service.dart';
import '../../../../auth/data/models/user_response_dto.dart';
import '../../../../auth/data/models/user_update_request_dto.dart';

class EditProfilePage extends StatefulWidget {
  final UserResponseDto user;

  const EditProfilePage({
    super.key,
    required this.user,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _surnameController;
  late TextEditingController _userNameController;
  late TextEditingController _birthdateController;
  DateTime? _selectedDate;
  bool _isLoading = false;
  String? _updateError; // Backend'den gelen update error

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name ?? '');
    _surnameController = TextEditingController(text: widget.user.surname ?? '');
    _userNameController = TextEditingController(text: widget.user.userName);
    _birthdateController = TextEditingController(
      text: widget.user.birthdate ?? '',
    );
    // Birthdate'i parse et
    if (widget.user.birthdate != null && widget.user.birthdate!.isNotEmpty) {
      try {
        _selectedDate = DateTime.parse(widget.user.birthdate!);
      } catch (e) {
        // Parse hatası durumunda null bırak
        if (kDebugMode) {
          debugPrint('Birthdate parse error: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _userNameController.dispose();
    _birthdateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(), // Şu anki tarihten ileri olamaz
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
        _birthdateController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _saveChanges() async {
    // Önceki error'u temizle
    setState(() {
      _updateError = null;
    });
    
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Username değiştiyse kontrol et
      final newUsername = _userNameController.text.trim();
      if (newUsername != widget.user.userName) {
        // Backend'de username kontrolü yapılacak
        // Şimdilik sadece devam ediyoruz
      }

      // Tüm alanlar zorunlu olduğu için null kontrolü yapmıyoruz
      final updateRequest = UserUpdateRequestDto(
        userName: newUsername,
        name: _nameController.text.trim(),
        surname: _surnameController.text.trim(),
        birthdate: _birthdateController.text.trim(),
      );

      await _authService.updateMe(updateRequest);

      // Başarılı - direkt geri dön (SnackBar yok)
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        // Backend error'u username field'ına set et
        setState(() {
          _updateError = errorMessage;
          _isLoading = false;
        });
        // Form'u yeniden validate et ki error gösterilsin
        _formKey.currentState?.validate();
      }
    } finally {
      if (mounted && _updateError == null) {
        setState(() {
          _isLoading = false;
        });
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
          icon: const Icon(Icons.arrow_back),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: AppTextStyles.heading2,
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveChanges,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          // Klavyeyi kapat
          FocusScope.of(context).unfocus();
        },
        behavior: HitTestBehavior.opaque,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xLarge),

              // Profile Picture Section
              Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.border,
                        width: 2,
                      ),
                      color: AppColors.surface,
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      size: 80,
                      color: AppColors.primary,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () {
                        // TODO: Implement photo picker
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Photo picker will be implemented soon'),
                          ),
                        );
                      },
                      child: Container(
                        width: 36,
                        height: 36,
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
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.small),

              // Camera instruction text
              Text(
                'Click camera icon to change photo',
                style: AppTextStyles.bodySecondary.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: AppSpacing.xLarge),

              // Name Input
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Name',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              AppInput(
                controller: _nameController,
                hint: 'Enter your name',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),

              const SizedBox(height: AppSpacing.xLarge),

              // Surname Input
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Surname',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              AppInput(
                controller: _surnameController,
                hint: 'Enter your surname',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Surname is required';
                  }
                  return null;
                },
              ),

              const SizedBox(height: AppSpacing.xLarge),

              // Username Input
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Username',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              AppInput(
                controller: _userNameController,
                hint: 'Enter your username',
                validator: (value) {
                  // Önce backend error'u kontrol et
                  if (_updateError != null) {
                    return _updateError;
                  }
                  
                  if (value == null || value.trim().isEmpty) {
                    return 'Username is required';
                  }
                  final trimmedValue = value.trim();
                  if (trimmedValue.length < 3) {
                    return 'Username must be at least 3 characters';
                  }
                  // Username sadece harf, rakam ve alt çizgi içerebilir
                  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmedValue)) {
                    return 'Username can only contain letters, numbers and underscore';
                  }
                  return null;
                },
                onChanged: () {
                  if (_updateError != null) {
                    setState(() => _updateError = null);
                  }
                },
              ),

              const SizedBox(height: AppSpacing.xLarge),

              // Birthdate Input
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Birthdate',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              GestureDetector(
                onTap: () => _selectDate(context),
                child: AbsorbPointer(
                  child: AppInput(
                    controller: _birthdateController,
                    hint: 'Select your birthdate',
                    suffixIcon: const Icon(Icons.calendar_today, color: AppColors.textSecondary),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Birthdate is required';
                      }
                      // Tarih formatını kontrol et
                      try {
                        final date = DateTime.parse(value.trim());
                        final now = DateTime.now();
                        // Şu anki tarihten ileri olamaz
                        if (date.isAfter(now)) {
                          return 'Birthdate cannot be in the future';
                        }
                      } catch (e) {
                        return 'Invalid date format';
                      }
                      return null;
                    },
                  ),
                ),
              ),

              // Bottom padding for scroll
              const SizedBox(height: AppSpacing.xLarge),
            ],
          ),
        ),
        ),
      ),
    );
  }
}


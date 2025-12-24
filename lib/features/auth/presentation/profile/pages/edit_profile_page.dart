import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_input.dart';
import '../../../../../core/widgets/app_button.dart';
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

  @override
  void initState() {
    super.initState();
    // Debug: Kullanıcı verilerini kontrol et
    print('📋 Edit Profile - User Data:');
    print('  Name: ${widget.user.name}');
    print('  Surname: ${widget.user.surname}');
    print('  Username: ${widget.user.userName}');
    print('  Birthdate: ${widget.user.birthdate}');
    
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
        print('⚠️ Birthdate parse error: $e');
        // Parse hatası durumunda null bırak
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

  Future<bool> _checkUsernameAvailability(String username) async {
    // Eğer username değişmediyse kontrol etme
    if (username == widget.user.userName) {
      return true;
    }
    
    try {
      // Backend'de username kontrolü yapılacak
      // Şimdilik sadece format kontrolü yapıyoruz
      // Backend'den 409 Conflict dönerse username alınmış demektir
      return true;
    } catch (e) {
      // Hata durumunda false döndür
      return false;
    }
  }

  Future<void> _saveChanges() async {
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true); // true döndürerek Settings sayfasına güncelleme yapıldığını bildir
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to update profile';
        final errorString = e.toString();
        
        // Backend'den gelen hata mesajlarını kontrol et
        if (errorString.contains('username') || errorString.contains('already exists') || errorString.contains('409')) {
          errorMessage = 'Username is already taken. Please choose another one.';
        } else if (errorString.contains('400') || errorString.contains('Bad Request')) {
          errorMessage = 'Invalid data. Please check all fields.';
        } else {
          errorMessage = errorString.replaceFirst('Exception: ', '');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
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
              SizedBox(
                height: 80, // Sabit yükseklik: input + error mesajı için
                child: AppInput(
                  controller: _nameController,
                  hint: 'Enter your name',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
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
              SizedBox(
                height: 80, // Sabit yükseklik: input + error mesajı için
                child: AppInput(
                  controller: _surnameController,
                  hint: 'Enter your surname',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Surname is required';
                    }
                    return null;
                  },
                ),
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
              SizedBox(
                height: 80, // Sabit yükseklik: diğer alanlarla aynı
                child: AppInput(
                  controller: _userNameController,
                  hint: 'Enter your username',
                  validator: (value) {
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
                ),
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
              SizedBox(
                height: 80, // Sabit yükseklik: input + error mesajı için
                child: GestureDetector(
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


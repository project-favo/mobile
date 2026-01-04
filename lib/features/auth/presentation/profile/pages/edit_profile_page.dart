import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
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
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedProfilePhoto;
  Uint8List? _currentProfilePhotoBytes; // Backend'den gelen profil fotoğrafı

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
    // Backend'den gelen profil fotoğrafını decode et
    if (widget.user.profilePhotoData != null && widget.user.profilePhotoData!.isNotEmpty) {
      try {
        _currentProfilePhotoBytes = base64Decode(widget.user.profilePhotoData!);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Profile photo decode error: $e');
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
            if (_selectedProfilePhoto != null || _currentProfilePhotoBytes != null)
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('Remove Photo'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedProfilePhoto = null;
                    _currentProfilePhotoBytes = null;
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
      
      // Profil fotoğrafını base64'e çevir
      String? profilePhotoBase64;
      String? profilePhotoMimeType;
      
      if (_selectedProfilePhoto != null) {
        profilePhotoBase64 = await _convertImageToBase64();
        profilePhotoMimeType = _selectedProfilePhoto!.mimeType ?? 'image/jpeg';
      } else if (_currentProfilePhotoBytes == null && widget.user.profilePhotoData != null) {
        // Fotoğraf silinmişse, boş string gönder (backend'e null göndermek için)
        // Backend'e null göndermek için field'ı göndermeyiz
      }

      // Update request - tüm alanları gönder (backend partial update destekliyor)
      final updateRequest = UserUpdateRequestDto(
        userName: newUsername,
        name: _nameController.text.trim(),
        surname: _surnameController.text.trim(),
        birthdate: _birthdateController.text.trim(),
        profilePhotoBase64: profilePhotoBase64,
        profilePhotoMimeType: profilePhotoMimeType,
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
              GestureDetector(
                onTap: _showPhotoSourceDialog,
                child: Stack(
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
                      child: _selectedProfilePhoto != null
                          ? ClipOval(
                              child: Image.file(
                                File(_selectedProfilePhoto!.path),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            )
                          : _currentProfilePhotoBytes != null
                              ? ClipOval(
                                  child: Image.memory(
                                    _currentProfilePhotoBytes!,
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : const Icon(
                                  Icons.person_outline_rounded,
                                  size: 80,
                                  color: AppColors.primary,
                                ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
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
                  ],
                ),
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


import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_input.dart';
import '../../../../../core/widgets/custom_snack_bar.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/app_datetime.dart';
import '../../../../../core/utils/user_display_name_prefs.dart';
import '../../../../../core/utils/username_input_rules.dart';
import '../../../../../core/utils/resolve_media_url.dart';
import '../../../../auth/data/services/auth_service.dart';
import '../../../../../core/utils/exceptions.dart';
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

class _EditProfilePageState extends State<EditProfilePage>
    with WidgetsBindingObserver {
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
  Uint8List? _currentProfilePhotoBytes;
  /// Kullanıcı "Remove Photo" dediğinde true; kayıtta sunucuya clear gider.
  bool _wantsToRemovePhoto = false;
  late bool _profileAnonymous;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nameController = TextEditingController(text: widget.user.name ?? '');
    _surnameController = TextEditingController(text: widget.user.surname ?? '');
    _userNameController = TextEditingController(text: widget.user.userName);
    _birthdateController = TextEditingController(
      text: widget.user.birthdate ?? '',
    );
    // Birthdate'i parse et
    if (widget.user.birthdate != null && widget.user.birthdate!.isNotEmpty) {
      try {
        _selectedDate = parseBackendDateTimeToLocal(widget.user.birthdate!);
      } catch (e) {
        // Parse hatası durumunda null bırak
        if (kDebugMode) {
          debugPrint('Birthdate parse error: $e');
        }
      }
    }
    // Base64 data (data URI olabilir) — decodeProfilePhotoBytes ile
    final fromData = decodeProfilePhotoBytes(widget.user.profilePhotoData);
    if (fromData != null && fromData.isNotEmpty) {
      _currentProfilePhotoBytes = fromData;
    }
    _profileAnonymous = widget.user.profileAnonymous;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_revalidateAccountOnResume());
    }
  }

  /// Profil düzenlerken askı — [getMe] → [_finalizeUserResponse] oturumu kapatır.
  Future<void> _revalidateAccountOnResume() async {
    try {
      await _authService.getMe();
    } on DeactivatedAccountException {
      // Oturum zaten kapatılıyor
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          _wantsToRemovePhoto = false;
        });
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Failed to pick image: ${e.toString()}',
          variant: CustomSnackBarVariant.error,
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
            if (_selectedProfilePhoto != null ||
                _currentProfilePhotoBytes != null ||
                (widget.user.profileImageUrl != null &&
                    widget.user.profileImageUrl!.trim().isNotEmpty) ||
                (widget.user.profilePhotoData != null &&
                    widget.user.profilePhotoData!.trim().isNotEmpty))
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('Remove Photo'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedProfilePhoto = null;
                    _currentProfilePhotoBytes = null;
                    _wantsToRemovePhoto = true;
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
        CustomSnackBar.show(
          context,
          message: 'Failed to process image: ${e.toString()}',
          variant: CustomSnackBarVariant.error,
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
      final newUsername = _userNameController.text.trim();
      final oldUsername = widget.user.userName.trim();
      final usernameUnchanged = newUsername == oldUsername;
      final onlyCaseChange =
          !usernameUnchanged &&
          newUsername.toLowerCase() == oldUsername.toLowerCase();
      final String? userNameForApi =
          (usernameUnchanged || onlyCaseChange) ? null : newUsername;

      if (onlyCaseChange) {
        await UserDisplayNamePrefs.instance.writePreferredDisplay(
          widget.user.id,
          newUsername,
        );
      }

      String? profilePhotoBase64;
      String? profilePhotoMimeType;
      final bool clearPhoto = _wantsToRemovePhoto;

      if (clearPhoto) {
        profilePhotoBase64 = null;
        profilePhotoMimeType = null;
      } else if (_selectedProfilePhoto != null) {
        profilePhotoBase64 = await _convertImageToBase64();
        profilePhotoMimeType = _selectedProfilePhoto!.mimeType ?? 'image/jpeg';
      }

      final updateRequest = UserUpdateRequestDto(
        userName: userNameForApi,
        name: _nameController.text.trim(),
        surname: _surnameController.text.trim(),
        birthdate: _birthdateController.text.trim(),
        profileAnonymous: _profileAnonymous,
        profilePhotoBase64: profilePhotoBase64,
        profilePhotoMimeType: profilePhotoMimeType,
        clearProfilePhoto: clearPhoto,
      );

      var fresh = await _authService.updateMe(updateRequest);
      // Girdi (İ, büyük/küçük harf) ile sunucunun döndürdüğü metin farklı olsa da kayıt başarılıysa
      // ekranda kullanıcının yazdığını göster
      if (userNameForApi != null || onlyCaseChange) {
        fresh = fresh.withUserName(newUsername);
      }
      final toReturn = clearPhoto ? fresh.withProfileMediaCleared() : fresh;

      if (mounted) {
        Navigator.pop(context, toReturn);
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
                      child: _wantsToRemovePhoto
                          ? const Icon(
                              Icons.person_outline_rounded,
                              size: 80,
                              color: AppColors.primary,
                            )
                          : _selectedProfilePhoto != null
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
                                  : (resolveMediaUrl(widget.user.profileImageUrl) !=
                                          null
                                      ? ClipOval(
                                          child: Image.network(
                                            resolveMediaUrl(
                                                    widget.user.profileImageUrl)!,
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                              Icons.person_outline_rounded,
                                              size: 80,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person_outline_rounded,
                                          size: 80,
                                          color: AppColors.primary,
                                        )),
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
                  if (_updateError != null) {
                    return _updateError;
                  }
                  return UsernameInputRules.validateForForm(value);
                },
                onChanged: () {
                  if (_updateError != null) {
                    setState(() => _updateError = null);
                  }
                },
              ),

              const SizedBox(height: AppSpacing.xLarge),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.medium,
                  vertical: AppSpacing.small,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Anonymous profile',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Others will see your name as A**** A****.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _profileAnonymous,
                      activeColor: AppColors.primary,
                      onChanged: (v) {
                        setState(() {
                          _profileAnonymous = v;
                        });
                      },
                    ),
                  ],
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
                        final date = parseBackendDateTimeToLocal(value.trim());
                        if (date == null) {
                          return 'Invalid date format';
                        }
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


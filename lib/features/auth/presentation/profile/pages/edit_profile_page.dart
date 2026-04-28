import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_input.dart';
import '../../../../../core/widgets/custom_snack_bar.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/image_picker_errors.dart';
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
  String? _updateError;
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedProfilePhoto;
  Uint8List? _currentProfilePhotoBytes;
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
    if (widget.user.birthdate != null && widget.user.birthdate!.isNotEmpty) {
      try {
        _selectedDate = parseBackendDateTimeToLocal(widget.user.birthdate!);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Birthdate parse error: $e');
        }
      }
    }
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

  Future<void> _revalidateAccountOnResume() async {
    try {
      await _authService.getMe();
    } on DeactivatedAccountException {
      // Session is already being closed
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
          message: messageForImagePickerError(e, source),
          variant: CustomSnackBarVariant.error,
        );
      }
    }
  }

  bool get _hasPhoto =>
      !_wantsToRemovePhoto &&
      (_selectedProfilePhoto != null ||
          _currentProfilePhotoBytes != null ||
          (resolveMediaUrl(widget.user.profileImageUrl) != null));

  void _showPhotoSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _buildSheetOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose from Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickProfilePhoto(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 8),
                _buildSheetOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Take a Photo',
                  onTap: () {
                    Navigator.pop(context);
                    _pickProfilePhoto(ImageSource.camera);
                  },
                ),
                if (_hasPhoto || _selectedProfilePhoto != null) ...[
                  const SizedBox(height: 8),
                  _buildSheetOption(
                    icon: Icons.delete_rounded,
                    label: 'Remove Photo',
                    isDestructive: true,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedProfilePhoto = null;
                        _currentProfilePhotoBytes = null;
                        _wantsToRemovePhoto = true;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? AppColors.error : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: isDestructive ? AppColors.error : AppColors.primary, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
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
      initialDate:
          _selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
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
        _birthdateController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _saveChanges() async {
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
        setState(() {
          _updateError = errorMessage;
          _isLoading = false;
        });
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

  Widget _buildProfileAvatar() {
    Widget avatarContent;

    if (_wantsToRemovePhoto) {
      avatarContent = const Icon(
        Icons.person_rounded,
        size: 64,
        color: Colors.white54,
      );
    } else if (_selectedProfilePhoto != null) {
      avatarContent = ClipOval(
        child: Image.file(
          File(_selectedProfilePhoto!.path),
          width: 110,
          height: 110,
          fit: BoxFit.cover,
        ),
      );
    } else if (_currentProfilePhotoBytes != null) {
      avatarContent = ClipOval(
        child: Image.memory(
          _currentProfilePhotoBytes!,
          width: 110,
          height: 110,
          fit: BoxFit.cover,
        ),
      );
    } else if (resolveMediaUrl(widget.user.profileImageUrl) != null) {
      avatarContent = ClipOval(
        child: Image.network(
          resolveMediaUrl(widget.user.profileImageUrl)!,
          width: 110,
          height: 110,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.person_rounded,
            size: 64,
            color: Colors.white54,
          ),
        ),
      );
    } else {
      avatarContent = const Icon(
        Icons.person_rounded,
        size: 64,
        color: Colors.white54,
      );
    }

    return GestureDetector(
      onTap: _showPhotoSourceDialog,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.5),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: avatarContent,
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
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.medium),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildFieldCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildLabeledField({
    required String label,
    required Widget field,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, isLast ? 14 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          field,
          if (!isLast)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Divider(height: 1, color: AppColors.border),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Form(
          key: _formKey,
          child: CustomScrollView(
            slivers: [
              _buildSliverHeader(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xLarge,
                    AppSpacing.xxLarge,
                    AppSpacing.xLarge,
                    AppSpacing.xLarge,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionLabel('PERSONAL INFO'),
                      _buildFieldCard([
                        _buildLabeledField(
                          label: 'Name',
                          field: AppInput(
                            controller: _nameController,
                            hint: 'Your name',
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Name is required';
                              }
                              return null;
                            },
                          ),
                        ),
                        _buildLabeledField(
                          label: 'Surname',
                          field: AppInput(
                            controller: _surnameController,
                            hint: 'Your surname',
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Surname is required';
                              }
                              return null;
                            },
                          ),
                        ),
                        _buildLabeledField(
                          label: 'Date of Birth',
                          isLast: true,
                          field: GestureDetector(
                            onTap: () => _selectDate(context),
                            child: AbsorbPointer(
                              child: AppInput(
                                controller: _birthdateController,
                                hint: 'Select birthdate',
                                suffixIcon: const Icon(
                                  Icons.calendar_month_rounded,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Birthdate is required';
                                  }
                                  try {
                                    final date =
                                        parseBackendDateTimeToLocal(value.trim());
                                    if (date == null) {
                                      return 'Invalid date format';
                                    }
                                    if (date.isAfter(DateTime.now())) {
                                      return 'Birthdate cannot be in the future';
                                    }
                                  } catch (_) {
                                    return 'Invalid date format';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                        ),
                      ]),

                      const SizedBox(height: AppSpacing.xxLarge),

                      _buildSectionLabel('ACCOUNT'),
                      _buildFieldCard([
                        _buildLabeledField(
                          label: 'Username',
                          isLast: true,
                          field: AppInput(
                            controller: _userNameController,
                            hint: 'your_username',
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
                        ),
                      ]),

                      const SizedBox(height: AppSpacing.xxLarge),

                      _buildSectionLabel('PRIVACY'),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.shield_rounded,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Anonymous Profile',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Others will see your name as A**** A****.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _profileAnonymous,
                                activeThumbColor: AppColors.primary,
                                activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                                onChanged: (v) {
                                  setState(() => _profileAnonymous = v);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveChanges,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xLarge),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliverHeader() {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: AppColors.primary,
      leading: IconButton(
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Edit Profile',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFB5003A),
                    AppColors.primary,
                    Color(0xFF6B001F),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _CirclePatternPainter()),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  _buildProfileAvatar(),
                  const SizedBox(height: 8),
                  Text(
                    'Tap photo to change',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CirclePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.2), 80, paint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.75), 55, paint);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 1.1), 70, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

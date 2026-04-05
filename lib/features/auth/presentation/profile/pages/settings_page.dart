import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../auth/data/services/auth_service.dart';
import '../../../../auth/data/models/user_response_dto.dart';
import '../widgets/profile_menu_item.dart';
import '../../../../../routes/app_routes.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/utils/resolve_media_url.dart';
import 'edit_profile_page.dart';
import 'change_password_page.dart';
import '../../email_verification_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = AuthService();
  UserResponseDto? _user;
  bool _isLoading = true;
  String? _errorMessage;
  bool _emailVerifyBusy = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      try {
        await FirebaseAuth.instance.currentUser?.reload();
      } catch (_) {}
      final user = await _authService.getMe();
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _showLogoutDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Log out',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          content: const Text(
            "Are you sure you want to log out? You'll need to login again to use the app.",
            style: TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.primary, width: 1),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _handleLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Log out',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleLogout() async {
    try {
      await _authService.signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Delete account',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          content: const Text(
            'This action is permanent and cannot be undone. Are you sure you want to delete your account?',
            style: TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.primary, width: 1),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _handleDeleteAccount();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resendBackendVerificationCode() async {
    setState(() => _emailVerifyBusy = true);
    try {
      await _authService.resendVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A new 5-digit code was sent to your email.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getUserFriendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _emailVerifyBusy = false);
    }
  }

  Future<void> _openEmailVerification({
    required String email,
    required bool onlyVerifyNoBackendLogin,
  }) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EmailVerificationPage(
          email: email,
          onlyVerifyNoBackendLogin: onlyVerifyNoBackendLogin,
          popOnSuccessWithResult: true,
        ),
      ),
    );
    if (ok == true && mounted) await _loadUserData();
  }

  Widget _emailVerificationSettingsCard() {
    final email = _user!.email;
    final ev = _user!.emailVerified;

    if (ev == true) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.success, size: 22),
            const SizedBox(width: AppSpacing.small),
            Text(
              'Email verified',
              style: AppTextStyles.bodySecondary.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (ev == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(AppSpacing.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Optional: verify your email with a 5-digit code.',
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.medium),
              TextButton(
                onPressed: _emailVerifyBusy
                    ? null
                    : () => _openEmailVerification(
                          email: email,
                          onlyVerifyNoBackendLogin: true,
                        ),
                child: const Text('Verify email'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
      child: Material(
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.mark_email_unread_outlined,
                      color: AppColors.primary, size: 24),
                  const SizedBox(width: AppSpacing.small),
                  Expanded(
                    child: Text(
                      'Verify your email',
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                'We sent a 5-digit code to your inbox. Enter it to finish verification.',
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.medium),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _emailVerifyBusy
                        ? null
                        : _resendBackendVerificationCode,
                    child: const Text('Resend code'),
                  ),
                  TextButton(
                    onPressed: _emailVerifyBusy
                        ? null
                        : () => _openEmailVerification(
                              email: email,
                              onlyVerifyNoBackendLogin: false,
                            ),
                    child: const Text('Enter code'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDeleteAccount() async {
    try {
      await _authService.deleteAccount();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        final errorMessage = ErrorHandler.getUserFriendlyMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          toolbarHeight: AppSpacing.toolbarHeight,
          title: const Text('Settings', style: AppTextStyles.HomeHeader,),
          centerTitle: true,
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
            child: const BackButton(
              color: AppColors.primary,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null || _user == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          toolbarHeight: AppSpacing.toolbarHeight,
          title: const Text('Settings', style: AppTextStyles.HomeHeader,),
          centerTitle: true,
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
            child: const BackButton(
              color: AppColors.primary,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: AppColors.error,
                ),
                const SizedBox(height: AppSpacing.large),
                Text(
                  _errorMessage ?? 'Failed to load user data',
                  style: AppTextStyles.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.large),
                ElevatedButton(
                  onPressed: _loadUserData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        toolbarHeight: AppSpacing.toolbarHeight,
        title: const Text('Settings', style: AppTextStyles.HomeHeader,),
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
          child: const BackButton(
            color: AppColors.primary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.large),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.logout),
                color: Colors.white,
                onPressed: _showLogoutDialog,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppColors.textSecondary.withOpacity(0.2),
          ),
        ),
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [
          const SizedBox(height: AppSpacing.xxLarge),

          // Avatar - Profil fotoğrafı varsa göster
          ProfileAvatar(
            radius: 45,
            imageUrl: _user!.profileImageUrl,
            memoryBytes: decodeProfilePhotoBytes(_user!.profilePhotoData),
            fallbackInitial: _user!.userName,
          ),

          const SizedBox(height: AppSpacing.large),

          // User Name - Backend'den gelen userName
          Text(
            _user!.userName,
            style: AppTextStyles.titleMedium,
          ),

          const SizedBox(height: AppSpacing.small),

          // Email - Backend'den gelen email
          Text(
            _user!.email,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: AppSpacing.large),
          _emailVerificationSettingsCard(),
          const SizedBox(height: AppSpacing.settingPages),

          Divider(
            thickness: 2,
            color: AppColors.textSecondary.withOpacity(0.2),
          ),
          // Menu Items
          ProfileMenuItem(
            title: 'Edit Profile',
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfilePage(user: _user!),
                ),
              );
              // Eğer profil güncellendiyse, kullanıcı bilgilerini yeniden yükle
              if (result == true) {
                await _loadUserData();
                // Profile sayfasını da güncellemek için true döndür (Settings'ten geri dönüldüğünde)
                if (mounted) {
                  // Settings sayfasından geri dönüldüğünde Profile sayfasına bilgi ver
                  Navigator.pop(context, true);
                }
              }
            },
          ),
          Divider(
            thickness: 2,
            color: AppColors.textSecondary.withOpacity(0.2),
          ),
          ProfileMenuItem(
            title: 'Notifications',
            onTap: () {},
          ),
          Divider(
            thickness: 2,
            color: AppColors.textSecondary.withOpacity(0.2),
          ),
          ProfileMenuItem(
            title: 'Change Password',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChangePasswordPage(),
                ),
              );
            },
          ),
          Divider(
            thickness: 2,
            color: AppColors.textSecondary.withOpacity(0.2),
          ),
          ProfileMenuItem(
            title: 'Delete Account',
            isDestructive: true,
            onTap: _showDeleteAccountDialog,
          ),
          Divider(
            thickness: 2,
            color: AppColors.textSecondary.withOpacity(0.2),
          ),
        ],
        ),
      ),
    );
  }
}


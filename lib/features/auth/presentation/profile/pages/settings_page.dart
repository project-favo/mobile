import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../auth/data/services/auth_service.dart';
import '../../../../auth/data/models/user_response_dto.dart';
import '../../../../../routes/app_routes.dart';
import '../../../../../core/widgets/profile_avatar.dart';
import '../../../../../core/utils/resolve_media_url.dart';
import 'edit_profile_page.dart';
import 'change_password_page.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../../../core/widgets/custom_snack_bar.dart';
import '../../backend_email_verification_page.dart';

class SettingsPage extends StatefulWidget {
  final UserResponseDto? initialUser;

  const SettingsPage({super.key, this.initialUser});

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
    if (widget.initialUser != null) {
      _user = widget.initialUser;
      _isLoading = false;
      unawaited(_loadUserData(silent: true));
    } else {
      _loadUserData();
    }
  }

  Future<void> _loadUserData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      _errorMessage = null;
    }

    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        unawaited(u.reload().catchError((_) {}));
      }
      final user = await _authService.getMe();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && _user != null) return;
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Log out',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: const Text(
            "Are you sure you want to log out? You'll need to sign in again to use the app.",
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _handleLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Log out',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    } catch (e) {
      if (!context.mounted) return;
      CustomSnackBar.show(
        context,
        message: ErrorHandler.getUserFriendlyMessage(e),
        variant: CustomSnackBarVariant.error,
      );
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Delete account',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: const Text(
            'This action is permanent and cannot be undone. Are you sure you want to delete your account?',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _handleDeleteAccount();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
      CustomSnackBar.show(
        context,
        message: 'A new verification email was sent.',
        variant: CustomSnackBarVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      CustomSnackBar.show(
        context,
        message: ErrorHandler.getUserFriendlyMessage(e),
        variant: CustomSnackBarVariant.error,
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
        builder: (_) => BackendEmailVerificationPage(
          email: email,
          popWithSuccessResult: true,
          navigateHomeOnSuccess: false,
          refreshProfileOnlyOnContinue: onlyVerifyNoBackendLogin,
        ),
      ),
    );
    if (ok == true && mounted) await _loadUserData();
  }

  Future<void> _handleDeleteAccount() async {
    try {
      await _authService.deleteAccount();
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    } catch (e) {
      if (!context.mounted) return;
      CustomSnackBar.show(
        context,
        message: ErrorHandler.getUserFriendlyMessage(e),
        variant: CustomSnackBarVariant.error,
      );
    }
  }

  Widget _buildEmailVerificationCard() {
    final email = _user!.email;
    final ev = _user!.emailVerified;

    if (ev == true) {
      return _buildInfoRow(
        icon: Icons.verified_rounded,
        iconColor: AppColors.success,
        iconBg: AppColors.success.withValues(alpha: 0.1),
        title: 'Email verified',
        subtitle: email,
      );
    }

    if (ev == null) {
      return _buildInfoRow(
        icon: Icons.mail_outline_rounded,
        iconColor: AppColors.textSecondary,
        iconBg: AppColors.border.withValues(alpha: 0.4),
        title: 'Email',
        subtitle: email,
        trailing: TextButton(
          onPressed: _emailVerifyBusy
              ? null
              : () => _openEmailVerification(
                    email: email,
                    onlyVerifyNoBackendLogin: true,
                  ),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      );
    }

    // ev == false — pending verification
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_email_unread_rounded, color: AppColors.warning.withValues(alpha: 0.85), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Verify your email',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Open the verification link in your email to finish. You can resend the email if needed.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _verifyActionButton(
                label: 'Resend email',
                onTap: _emailVerifyBusy ? null : _resendBackendVerificationCode,
              ),
              const SizedBox(width: 8),
              _verifyActionButton(
                label: 'Open verification',
                onTap: _emailVerifyBusy
                    ? null
                    : () => _openEmailVerification(
                          email: email,
                          onlyVerifyNoBackendLogin: false,
                        ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _verifyActionButton({required String label, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xLarge, 0, AppSpacing.xLarge, AppSpacing.medium),
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

  Widget _buildMenuCard(List<_MenuItem> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
      child: Container(
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
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _buildMenuRow(items[i], isLast: i == items.length - 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuRow(_MenuItem item, {required bool isLast}) {
    return Column(
      children: [
        InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.vertical(
            bottom: isLast ? const Radius.circular(16) : Radius.zero,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: item.isDestructive
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.icon,
                    size: 18,
                    color: item.isDestructive ? AppColors.error : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: item.isDestructive ? AppColors.error : AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: item.isDestructive ? AppColors.error.withValues(alpha: 0.5) : AppColors.border,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Padding(
            padding: EdgeInsets.only(left: 68),
            child: Divider(height: 1, color: AppColors.border),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
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
            'Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          centerTitle: true,
        ),
        body: const SettingsPageSkeleton(),
      );
    }

    if (_errorMessage != null || _user == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
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
            'Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline_rounded, size: 32, color: AppColors.error),
                ),
                const SizedBox(height: AppSpacing.xLarge),
                Text(
                  _errorMessage ?? 'Failed to load user data',
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xLarge),
                ElevatedButton(
                  onPressed: _loadUserData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                  child: const Text('Try again', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final user = _user!;
    final firstName = (user.name ?? '').trim();
    final lastName = (user.surname ?? '').trim();
    final fullName = [firstName, lastName].where((e) => e.isNotEmpty).join(' ');

    final accountItems = [
      _MenuItem(
        icon: Icons.person_rounded,
        title: 'Edit Profile',
        onTap: () async {
          final result = await Navigator.push<dynamic>(
            context,
            MaterialPageRoute(builder: (_) => EditProfilePage(user: user)),
          );
          if (result is UserResponseDto) {
            if (!mounted) return;
            setState(() => _user = result);
            Navigator.pop(context, result);
          } else if (result == true) {
            await _loadUserData();
            if (!mounted) return;
            Navigator.pop(context, true);
          }
        },
      ),
    ];

    final securityItems = [
      _MenuItem(
        icon: Icons.lock_rounded,
        title: 'Change Password',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
        ),
      ),
    ];

    final dangerItems = [
      _MenuItem(
        icon: Icons.delete_forever_rounded,
        title: 'Delete Account',
        isDestructive: true,
        onTap: _showDeleteAccountDialog,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
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
              'Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  onPressed: _showLogoutDialog,
                  icon: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.logout_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
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
                  Positioned.fill(child: CustomPaint(painter: _CirclePatternPainter())),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        ProfileAvatar(
                          radius: 40,
                          imageUrl: user.profileImageUrl,
                          memoryBytes: decodeProfilePhotoBytes(user.profilePhotoData),
                          fallbackInitial: user.userName,
                        ),
                        const SizedBox(height: 8),
                        if (fullName.isNotEmpty)
                          Text(
                            fullName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        Text(
                          '@${user.userName}',
                          style: TextStyle(
                            fontSize: 13,
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
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Email verification status
                  _buildEmailVerificationCard(),

                  const SizedBox(height: AppSpacing.xxLarge),

                  _buildSectionLabel('ACCOUNT'),
                  _buildMenuCard(accountItems),

                  const SizedBox(height: AppSpacing.xxLarge),

                  _buildSectionLabel('SECURITY'),
                  _buildMenuCard(securityItems),

                  const SizedBox(height: AppSpacing.xxLarge),

                  _buildSectionLabel('DANGER ZONE'),
                  _buildMenuCard(dangerItems),

                  const SizedBox(height: 40),

                  // Log out button at the bottom
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _showLogoutDialog,
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text(
                          'Log out',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });
}

class _CirclePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.2), 70, paint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.75), 50, paint);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 1.1), 65, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

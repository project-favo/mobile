import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../auth/data/services/auth_service.dart';
import '../../../../auth/data/models/user_response_dto.dart';
import '../widgets/profile_menu_item.dart';

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
      final user = await _authService.getMe();
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage ?? 'Failed to load user data',
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.large),
              ElevatedButton(
                onPressed: _loadUserData,
                child: const Text('Retry'),
              ),
            ],
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
                onPressed: () {
                  // TODO: logout modal
                },
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

      body: Column(
        children: [
          const SizedBox(height: AppSpacing.xxLarge),

          // Avatar
          CircleAvatar(
            radius: 45,
            backgroundColor: AppColors.background,
            child: const Icon(
              Icons.person_outline_rounded,
              size: 50,
              color: AppColors.primary,
            ),
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

          const SizedBox(height: AppSpacing.settingPages),

          Divider(
            thickness: 2,
            color: AppColors.textSecondary.withOpacity(0.2),
          ),
          // Menu Items
          ProfileMenuItem(
            title: 'Edit Profile',
            onTap: () {},
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
            onTap: () {},
          ),
          Divider(
            thickness: 2,
            color: AppColors.textSecondary.withOpacity(0.2),
          ),
          ProfileMenuItem(
            title: 'Delete Account',
            isDestructive: true,
            onTap: () {},
          ),
          Divider(
            thickness: 2,
            color: AppColors.textSecondary.withOpacity(0.2),
          ),
        ],
      ),
    );
  }
}


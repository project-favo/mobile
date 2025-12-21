import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../widgets/profile_menu_item.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
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

          Text(
            'Özge Tontu',
            style: AppTextStyles.titleMedium,
          ),

          const SizedBox(height: 0),

          Text(
            '@ozgetnt',
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.grey,
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

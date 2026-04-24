import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Segmented tab bar for feed-style screens: soft track, floating selection pill,
/// primary accent on labels instead of a full solid brand block.
class FeedScreenTabBar extends StatelessWidget {
  const FeedScreenTabBar({
    super.key,
    required this.controller,
    required this.tabLabels,
  });

  final TabController controller;
  final List<String> tabLabels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: AppColors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: TabBar(
          controller: controller,
          isScrollable: false,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          indicatorPadding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          dividerColor: Colors.transparent,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: tabLabels.length > 3 ? 12 : 13,
            letterSpacing: 0.1,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: tabLabels.length > 3 ? 12 : 13,
            letterSpacing: 0.1,
          ),
          tabs: [for (final t in tabLabels) Tab(text: t)],
        ),
      ),
    );
  }
}

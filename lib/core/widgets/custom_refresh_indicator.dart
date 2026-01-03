import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Custom pull to refresh indicator with brand logo animation
class CustomRefreshIndicator extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const CustomRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      strokeWidth: 3.0,
      displacement: 40.0,
      child: child, // Custom refresh indicator with brand styling
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Kompakt sayfalama: yuvarlatılmış çip + ok ikonları (önceki / sonraki).
class PagedNavigationBar extends StatelessWidget {
  const PagedNavigationBar({
    super.key,
    required this.currentPage1Based,
    required this.totalPages,
    required this.canGoPrevious,
    required this.canGoNext,
    this.isLoadingNext = false,
    this.onPrevious,
    this.onNext,
    this.backgroundColor,
    this.showTopDivider = true,
  });

  final int currentPage1Based;
  final int totalPages;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool isLoadingNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Color? backgroundColor;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    final disabled = AppColors.textSecondary.withValues(alpha: 0.35);
    final fill = backgroundColor ?? AppColors.background;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTopDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.textSecondary.withValues(alpha: 0.1),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.medium,
            AppSpacing.small,
            AppSpacing.medium,
            AppSpacing.medium,
          ),
          child: Center(
            child: Semantics(
              label: 'Pagination, page $currentPage1Based of $totalPages',
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.55),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NavIconButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Previous page',
                      enabled: canGoPrevious && onPrevious != null,
                      onPressed: canGoPrevious && onPrevious != null
                          ? () {
                              HapticFeedback.selectionClick();
                              onPrevious!();
                            }
                          : null,
                      dimmedColor: disabled,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.medium,
                      ),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.small,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          '$currentPage1Based / $totalPages',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    _NavIconButton(
                      icon: Icons.chevron_right_rounded,
                      tooltip: 'Next page',
                      enabled: canGoNext &&
                          onNext != null &&
                          !isLoadingNext,
                      isLoading: isLoadingNext,
                      onPressed: canGoNext &&
                              onNext != null &&
                              !isLoadingNext
                          ? () {
                              HapticFeedback.selectionClick();
                              onNext!();
                            }
                          : null,
                      dimmedColor: disabled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    required this.dimmedColor,
    this.isLoading = false,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onPressed;
  final Color dimmedColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    return Material(
      color: active
          ? AppColors.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 26,
                      color: active ? AppColors.primary : dimmedColor,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// List pagination footer: compact status when everything fits on one page;
/// clear prev/next controls and progress when multiple pages.
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
    this.rangeStart1Based,
    this.rangeEnd1Based,
    this.rangeTotal,
    this.itemNounPlural = 'items',
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

  /// Optional 1-based inclusive range of rows on this page (`rangeTotal` = full list).
  final int? rangeStart1Based;
  final int? rangeEnd1Based;
  final int? rangeTotal;

  /// Plural label, e.g. `notifications`, `activities`.
  final String itemNounPlural;

  bool get _hasRange =>
      rangeStart1Based != null &&
      rangeEnd1Based != null &&
      rangeTotal != null &&
      rangeTotal! > 0;

  bool get _singlePage => totalPages <= 1;

  @override
  Widget build(BuildContext context) {
    final fill = backgroundColor ?? AppColors.background;
    final dividerColor = AppColors.textSecondary.withValues(alpha: 0.12);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTopDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: dividerColor,
          ),
        ColoredBox(
          color: fill,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.medium,
              10,
              AppSpacing.medium,
              12,
            ),
            child: _singlePage
                ? _SinglePageStatus(
                    rangeTotal: rangeTotal,
                    itemNounPlural: itemNounPlural,
                  )
                : _MultiPagePager(
                    currentPage1Based: currentPage1Based,
                    totalPages: totalPages,
                    canGoPrevious: canGoPrevious,
                    canGoNext: canGoNext,
                    isLoadingNext: isLoadingNext,
                    onPrevious: onPrevious,
                    onNext: onNext,
                    hasRange: _hasRange,
                    rangeStart1Based: rangeStart1Based,
                    rangeEnd1Based: rangeEnd1Based,
                    rangeTotal: rangeTotal,
                  ),
          ),
        ),
      ],
    );
  }
}

class _SinglePageStatus extends StatelessWidget {
  const _SinglePageStatus({
    required this.rangeTotal,
    required this.itemNounPlural,
  });

  final int? rangeTotal;
  final String itemNounPlural;

  @override
  Widget build(BuildContext context) {
    final n = rangeTotal;
    final String line;
    if (n == null) {
      line = 'Everything fits on one page.';
    } else if (n == 0) {
      line = 'No items to paginate.';
    } else if (n == 1) {
      line = 'Showing 1 $itemNounPlural.';
    } else {
      line = 'All $n $itemNounPlural on one page.';
    }

    return Semantics(
      label: line,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.45),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.medium,
            vertical: AppSpacing.small + 2,
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 22,
                color: AppColors.primary.withValues(alpha: 0.75),
              ),
              const SizedBox(width: AppSpacing.small + 2),
              Expanded(
                child: Text(
                  line,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MultiPagePager extends StatelessWidget {
  const _MultiPagePager({
    required this.currentPage1Based,
    required this.totalPages,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.isLoadingNext,
    required this.onPrevious,
    required this.onNext,
    required this.hasRange,
    required this.rangeStart1Based,
    required this.rangeEnd1Based,
    required this.rangeTotal,
  });

  final int currentPage1Based;
  final int totalPages;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool isLoadingNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool hasRange;
  final int? rangeStart1Based;
  final int? rangeEnd1Based;
  final int? rangeTotal;

  @override
  Widget build(BuildContext context) {
    final safeTotal = totalPages < 1 ? 1 : totalPages;
    final progress = (currentPage1Based.clamp(1, safeTotal)) / safeTotal;

    return Semantics(
      label:
          'Page $currentPage1Based of $safeTotal${hasRange ? ', rows ${rangeStart1Based!} through ${rangeEnd1Based!} of ${rangeTotal!}' : ''}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PagerSideButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous page',
                enabled: canGoPrevious && onPrevious != null,
                onPressed: canGoPrevious && onPrevious != null
                    ? () {
                        HapticFeedback.lightImpact();
                        onPrevious!();
                      }
                    : null,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Page $currentPage1Based / $safeTotal',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (hasRange) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${rangeStart1Based!}–${rangeEnd1Based!} of ${rangeTotal!}',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor:
                              AppColors.border.withValues(alpha: 0.35),
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _PagerSideButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next page',
                enabled: canGoNext && onNext != null && !isLoadingNext,
                isLoading: isLoadingNext,
                onPressed: canGoNext && onNext != null && !isLoadingNext
                    ? () {
                        HapticFeedback.lightImpact();
                        onNext!();
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagerSideButton extends StatelessWidget {
  const _PagerSideButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    this.isLoading = false,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.textSecondary.withValues(alpha: 0.06),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.primary,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 28,
                      color: active
                          ? AppColors.primary
                          : AppColors.textSecondary.withValues(alpha: 0.35),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

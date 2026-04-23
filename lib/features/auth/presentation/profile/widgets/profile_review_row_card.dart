import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/uniform_product_thumbnail.dart';
import '../../../data/models/review_dto.dart';

/// Profil ekranlarında sabit yükseklikli yorum satırı (metin taşması … ile kesilir).
class ProfileReviewRowCard extends StatelessWidget {
  static const double thumbSize = 92;
  static const double cardHeight = thumbSize + AppSpacing.large * 2;

  final ReviewDto review;
  final String? productImageUrl;
  /// [ReviewDto.isProductNotListed] + prefetch (404) + [ProductDto.isProductNotListed]
  final bool isProductNotListed;
  final bool youReportedThisReview;
  final bool youReportedThisProduct;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const ProfileReviewRowCard({
    super.key,
    required this.review,
    required this.productImageUrl,
    this.isProductNotListed = false,
    this.youReportedThisReview = false,
    this.youReportedThisProduct = false,
    this.onTap,
    this.onDelete,
  });

  /// Tek parça metin: `title · description` birleştirmesi satır sonlarında bozuk
  /// parçalar üretiyordu. Önce açıklama, yoksa başlık (üç nokta sadece [Text] overflow).
  static String previewText(ReviewDto r) {
    final tit = r.title.trim();
    final desc = r.description?.trim() ?? '';
    if (desc.isNotEmpty) return desc;
    return tit;
  }

  @override
  Widget build(BuildContext context) {
    final preview = previewText(review);
    final suspended = isProductNotListed;
    final hasReportInfo = youReportedThisReview || youReportedThisProduct;
    final rowHeight = cardHeight + (hasReportInfo && !suspended ? 24 : 0);

    final middleColumn = SizedBox(
      height: (hasReportInfo && !suspended) ? thumbSize + 24 : thumbSize,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasReportInfo && !suspended)
            Padding(
              padding: const EdgeInsets.only(
                bottom: AppSpacing.small,
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (youReportedThisReview)
                    const _YouReportedChip(
                      label: 'Reported (review)',
                    ),
                  if (youReportedThisProduct)
                    const _YouReportedChip(
                      label: 'Reported (product)',
                    ),
                ],
              ),
            ),
          if (!suspended) ...[
            Text(
              review.productName,
              style: AppTextStyles.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.small),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  preview,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                  maxLines: hasReportInfo ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.star_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${review.rating} / 5',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ] else
            const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );

    final tappableOrSuspended = suspended
        ? _SuspendedLeftBlock(
            productImageUrl: productImageUrl,
            thumbSize: thumbSize,
            middleColumn: middleColumn,
          )
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                UniformProductThumbnail(
                  imageUrl: productImageUrl,
                  size: thumbSize,
                ),
                const SizedBox(width: AppSpacing.large),
                Expanded(child: middleColumn),
              ],
            ),
          );

    return Container(
      height: rowHeight,
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: suspended
              ? AppColors.primary.withValues(alpha: 0.28)
              : AppColors.border.withValues(alpha: 0.45),
          width: suspended ? 1.2 : 1,
        ),
        boxShadow:
            suspended
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: tappableOrSuspended),
          if (onDelete != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.small),
              child: Tooltip(
                message: 'Delete review',
                child: Material(
                  color: AppColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.75),
                    ),
                  ),
                  child: InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Koyu perde + marka stiline uyumlu askı rozet; [AbsorbPointer] detayı engeller
/// (sil ayrı sütunda).
class _SuspendedLeftBlock extends StatelessWidget {
  const _SuspendedLeftBlock({
    required this.productImageUrl,
    required this.thumbSize,
    required this.middleColumn,
  });

  final String? productImageUrl;
  final double thumbSize;
  final Widget middleColumn;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.32,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  UniformProductThumbnail(
                    imageUrl: productImageUrl,
                    size: thumbSize,
                  ),
                  const SizedBox(width: AppSpacing.large),
                  Expanded(child: middleColumn),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.36),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2EDED),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.remove_shopping_cart_outlined,
                          size: 15,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'SUSPENDED',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            letterSpacing: 1.4,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Not available in the store',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YouReportedChip extends StatelessWidget {
  final String label;

  const _YouReportedChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.medium,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          height: 1.2,
        ),
      ),
    );
  }
}

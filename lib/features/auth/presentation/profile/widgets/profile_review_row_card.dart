import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/uniform_product_thumbnail.dart';
import '../../../data/models/review_dto.dart';

/// Profil ekranlarında sabit yükseklikli yorum satırı (metin taşması … ile kesilir).
/// Askıdaki ürün yorumları üstte filtrelenir; bu widget yalnızca vitrinde görünen satırlar için kullanılır.
class ProfileReviewRowCard extends StatelessWidget {
  static const double thumbSize = 92;
  static const double cardHeight = thumbSize + AppSpacing.large * 2;

  final ReviewDto review;
  final String? productImageUrl;
  final bool youReportedThisReview;
  final bool youReportedThisProduct;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const ProfileReviewRowCard({
    super.key,
    required this.review,
    required this.productImageUrl,
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
    final hasReportInfo = youReportedThisReview || youReportedThisProduct;
    final rowHeight = cardHeight + (hasReportInfo ? 24 : 0);

    final middleColumn = SizedBox(
      height: hasReportInfo ? thumbSize + 24 : thumbSize,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasReportInfo)
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
              if (review.mediaList.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.photo_camera_outlined,
                    size: 13,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
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
          color: AppColors.border.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
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
            ),
          ),
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

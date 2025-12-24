import 'package:flutter/material.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_colors.dart';

class TopProductList extends StatelessWidget {
  final String imageUrl;
  final String title;

  const TopProductList({
    super.key,
    required this.imageUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 165, // Biraz daha geniş, ama ana kartlardan küçük
      decoration: BoxDecoration(
        color: AppColors.primary, // Favo rengi arka plan
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // İçeriğe göre boyutlan
        children: [
          // Ürün resmi - Beyaz arka planlı container içinde
          Container(
            height: 110, // Biraz daha büyük resim
            width: double.infinity,
            margin: const EdgeInsets.all(AppSpacing.medium),
            decoration: BoxDecoration(
              borderRadius: AppDecorations.cardRadius,
              color: Colors.white,
            ),
            child: ClipRRect(
              borderRadius: AppDecorations.cardRadius,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.white,
                    child: const Icon(
                      Icons.image_not_supported,
                      color: AppColors.textSecondary,
                    ),
                  );
                },
              ),
            ),
          ),

          // Başlık - Beyaz text, sadece yan padding (alt padding yok)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.medium,
              0,
              AppSpacing.medium,
              AppSpacing.medium, // Sadece minimum padding
            ),
            child: Text(
              title,
              style: AppTextStyles.productTitle.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13, // Biraz daha küçük font
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

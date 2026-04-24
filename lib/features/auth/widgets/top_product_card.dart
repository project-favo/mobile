import 'package:flutter/material.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/routes/custom_page_transitions.dart';
import '../data/models/product_dto.dart';
import '../presentation/review/pages/review_page.dart';

class TopProductList extends StatefulWidget {
  final ProductDto product;
  final int rank; // 1, 2, 3, etc.

  const TopProductList({
    super.key,
    required this.product,
    required this.rank,
  });

  @override
  State<TopProductList> createState() => _TopProductListState();
}

class _TopProductListState extends State<TopProductList> {
  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Top picks kutusu 164×154 — 800×800 kare görsel için kare cache yeterli
    final topImgSide = (164 * dpr).round().clamp(140, 600);
    final topImgW = topImgSide;
    final topImgH = topImgSide;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          SlideRightRoute(
            page: ReviewPage(product: widget.product),
          ),
        );
      },
      child: Container(
        width: 180,
        height: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppDecorations.softPrimaryGlow(AppColors.primary),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                height: 154,
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: AppDecorations.cardRadius,
                  color: Colors.white,
                ),
                child: ClipRRect(
                  borderRadius: AppDecorations.cardRadius,
                  child: Image.network(
                    widget.product.imageURL,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    cacheWidth: topImgW,
                    cacheHeight: topImgH,
                    filterQuality: FilterQuality.medium,
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
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${widget.rank}',
                    style: AppTextStyles.bodyBold.copyWith(
                      color: AppColors.primary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

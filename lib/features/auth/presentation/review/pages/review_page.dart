import 'package:flutter/material.dart';
import '../widgets/review_card.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../data/models/product_dto.dart';

class ReviewPage extends StatelessWidget {
  final ProductDto product;

  const ReviewPage({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// PRODUCT IMAGE SECTION
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  product.imageURL,
                  height: 230,
                  width: double.infinity,
                  fit: BoxFit.fitHeight,
                ),
              ),
              const SizedBox(height: AppSpacing.xLarge),

              /// TITLE + FAVORITE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: AppTextStyles.heading1,
                      maxLines: 2,
                    ),
                  ),
                  Icon(Icons.favorite_border, color: AppColors.primary, size: 30,),
                ],
              ),
              Text(
                product.tag.name.toUpperCase(),
                style: AppTextStyles.productCardCategory,
              ),
              const SizedBox(height: AppSpacing.xLarge),

              /// RATING STARS
              Row(
                children: List.generate(
                  5,
                      (i) => Icon(Icons.star,
                      size: 30,
                      color: i < 4 ? AppColors.primary : AppColors.textSecondary),
                ),
              ),

              /// DESCRIPTION
              Text(
                product.description ?? "",
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xLarge),

              /// REVIEWS TITLE
              Text("Reviews", style: AppTextStyles.heading2),
              const SizedBox(height: AppSpacing.medium),

              /// MOCK REVIEW ITEM
              ReviewCard(
                username: "@iremnurc",
                content:
                "The color is elegant and matches perfectly with neutral-toned rooms",
                rating: 5,
                isSponsored: true,
              ),
              const SizedBox(height: AppSpacing.large),

              ReviewCard(
                username: "@sophia",
                content:
                "I'm really impressed with the quality of this blanket. The fabric feels soft and premium",
                rating: 4,
              ),

              const SizedBox(height: AppSpacing.xxLarge),
            ],
          ),
        ),
      ),

      /// ADD REVIEW BUTTON
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: AppButton(
          text: "Add a Review",
          onPressed: () {
            // TODO: Navigate to write-review form
          },
          isLoading: false,
        ),
      ),
    );
  }
}
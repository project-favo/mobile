import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

/// Shown when a product search has no matches — invite users to request additions by email.
class ProductRequestNotice extends StatelessWidget {
  const ProductRequestNotice({super.key, this.paddingTop = AppSpacing.large});

  static const String requestEmail = 'ctis411.09@gmail.com';

  final double paddingTop;

  @override
  Widget build(BuildContext context) {
    final base = AppTextStyles.bodySecondary.copyWith(height: 1.45);
    return Padding(
      padding: EdgeInsets.only(top: paddingTop),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: base,
          children: [
            const TextSpan(
              text:
                  "If the product you're looking for isn't in our app yet, you can ask us to add it by emailing ",
            ),
            TextSpan(
              text: requestEmail,
              style: base.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const TextSpan(text: '. Happy searching!'),
          ],
        ),
      ),
    );
  }
}

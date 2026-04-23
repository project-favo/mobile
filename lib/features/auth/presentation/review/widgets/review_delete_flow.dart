import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../data/repositories/review_repository.dart';

/// Kullanıcı yalnızca kendi yorumuna silme; sunucu da kontrol (DELETE /api/reviews/{id}).
class ReviewDeleteFlow {
  ReviewDeleteFlow._();

  static const String popResultDeleted = 'review_deleted';

  static Future<bool> confirmAndDelete(
    BuildContext context, {
    required ReviewRepository repository,
    required SessionHelper sessionHelper,
    required String reviewId,
  }) async {
    if (reviewId.trim().isEmpty) return false;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete review?'),
        content: const Text(
          'Are you sure you want to delete this review? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return false;

    try {
      final token = await sessionHelper.ensureSession();
      if (token == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in to delete your review'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return false;
      }
      await repository.deleteReview(token, reviewId);
      if (!context.mounted) return true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Deleted'),
          content: const Text('Your review was deleted successfully.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserFriendlyMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    }
  }
}

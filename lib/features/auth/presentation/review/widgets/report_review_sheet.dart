import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/exceptions.dart';
import '../../../../../core/utils/review_report_storage.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/repositories/review_repository.dart';

bool _reviewReportFlowBusy = false;

/// Review’ı tek adımda işaretle: neden seçimi yok; `OTHER` ile API’ye gönderilir.
Future<void> openReviewReportFlow(
  BuildContext context, {
  required String reviewId,
}) async {
  if (_reviewReportFlowBusy) return;
  _reviewReportFlowBusy = true;
  final repository = ReviewRepository();
  final sessionHelper = SessionHelper();
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to report a review'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    await ReviewReportStorage.hydrateForCurrentUser();
    if (!context.mounted) return;
    if (ReviewReportStorage.hasReportedSync(reviewId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already reported'),
          backgroundColor: AppColors.textSecondary,
        ),
      );
      return;
    }
    final token = await sessionHelper.ensureSession();
    if (!context.mounted) return;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to report'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    try {
      await repository.reportReview(
        token,
        reviewId,
        ReportReviewRequestDto(
          reason: 'OTHER',
          notes: null,
        ),
      );
      await ReviewReportStorage.markReported(reviewId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Reported'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (e is ReviewAlreadyReportedException) {
        await ReviewReportStorage.markReported(reviewId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Already reported'),
              backgroundColor: AppColors.textSecondary,
            ),
          );
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserFriendlyMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  } finally {
    _reviewReportFlowBusy = false;
  }
}

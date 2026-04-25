import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/widgets/custom_snack_bar.dart';
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
      CustomSnackBar.show(
        context,
        message: 'Please sign in to report a review',
        variant: CustomSnackBarVariant.error,
      );
      return;
    }
    await ReviewReportStorage.hydrateForCurrentUser();
    if (!context.mounted) return;
    if (ReviewReportStorage.hasReportedSync(reviewId)) {
      CustomSnackBar.show(
        context,
        message: 'Already reported',
        variant: CustomSnackBarVariant.neutral,
      );
      return;
    }
    final token = await sessionHelper.ensureSession();
    if (!context.mounted) return;
    if (token == null) {
      CustomSnackBar.show(
        context,
        message: 'Please sign in to report',
        variant: CustomSnackBarVariant.error,
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
        CustomSnackBar.show(
          context,
          message: 'Reported',
          variant: CustomSnackBarVariant.primary,
        );
      }
    } catch (e) {
      if (e is ReviewAlreadyReportedException) {
        await ReviewReportStorage.markReported(reviewId);
        if (context.mounted) {
          CustomSnackBar.show(
            context,
            message: 'Already reported',
            variant: CustomSnackBarVariant.neutral,
          );
        }
        return;
      }
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: ErrorHandler.getUserFriendlyMessage(e),
          variant: CustomSnackBarVariant.error,
        );
      }
    }
  } finally {
    _reviewReportFlowBusy = false;
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'content_availability_messages.dart';

/// Professional alert when content or a user profile can’t be shown; [onContinue] runs after OK.
/// Uses [AppColors.primary] for the action (same pattern as other branded dialogs in the app).
Future<void> showContentUnavailableDialog(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = kDialogButtonContinue,
  required Future<void> Function() onContinue,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        title,
        style: AppTextStyles.heading3.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
      content: Text(
        message,
        style: AppTextStyles.body.copyWith(
          color: AppColors.textSecondary,
          height: 1.45,
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            Navigator.of(ctx).pop();
            await onContinue();
          },
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}

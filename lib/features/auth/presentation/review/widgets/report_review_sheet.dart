import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../data/models/review_dto.dart';
import '../../../data/repositories/review_repository.dart';

class _ReasonOption {
  const _ReasonOption({required this.label, required this.apiValue});

  final String label;
  final String apiValue;
}

const List<_ReasonOption> _kReasons = [
  _ReasonOption(label: 'Spam or misleading', apiValue: 'SPAM'),
  _ReasonOption(label: 'Harassment or hate', apiValue: 'HARASSMENT'),
  _ReasonOption(label: 'Inappropriate content', apiValue: 'INAPPROPRIATE'),
  _ReasonOption(label: 'Misleading review', apiValue: 'MISLEADING'),
  _ReasonOption(label: 'Other', apiValue: 'OTHER'),
];

/// Review raporu: neden + isteğe bağlı açıklama, `ReviewRepository.reportReview`.
/// Başarılı gönderimde `true` döner (çağıran SnackBar gösterebilir).
Future<bool> showReportReviewSheet(
  BuildContext context, {
  required String reviewId,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _ReportReviewSheetBody(reviewId: reviewId),
  );
  return submitted == true;
}

class _ReportReviewSheetBody extends StatefulWidget {
  const _ReportReviewSheetBody({required this.reviewId});

  final String reviewId;

  @override
  State<_ReportReviewSheetBody> createState() => _ReportReviewSheetBodyState();
}

class _ReportReviewSheetBodyState extends State<_ReportReviewSheetBody> {
  final ReviewRepository _repository = ReviewRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final TextEditingController _details = TextEditingController();

  String _reason = _kReasons.first.apiValue;
  bool _submitting = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final token = await _sessionHelper.ensureSession();
      if (token == null) {
        throw Exception('Please sign in to report');
      }
      await _repository.reportReview(
        token,
        widget.reviewId,
        ReportReviewRequestDto(
          reason: _reason,
          description: _details.text,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getUserFriendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xLarge,
            AppSpacing.large,
            AppSpacing.xLarge,
            AppSpacing.xLarge,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Report review', style: AppTextStyles.heading3),
              const SizedBox(height: AppSpacing.small),
              Text(
                'Tell us what is wrong. Our team will review it.',
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.large),
              ..._kReasons.map((r) {
                return RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: r.apiValue,
                  groupValue: _reason,
                  onChanged: _submitting
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => _reason = v);
                        },
                  title: Text(r.label, style: AppTextStyles.body),
                );
              }),
              const SizedBox(height: AppSpacing.medium),
              TextField(
                controller: _details,
                enabled: !_submitting,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Details (optional)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.large),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit report'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

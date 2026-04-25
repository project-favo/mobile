import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Uygulama genelinde tek tip [SnackBar] — [ScaffoldMessenger] ile gösterilir.
enum CustomSnackBarVariant {
  /// Açık zemin, koyu metin (bilgi / genel).
  neutral,

  /// Yeşil arka plan (başarı).
  success,

  /// Marka rengi arka plan (onay / vurgulu bilgi).
  primary,

  /// Kırmızı arka plan (hata / uyarı).
  error,
}

abstract final class CustomSnackBar {
  const CustomSnackBar._();

  static Color _background(CustomSnackBarVariant v) {
    switch (v) {
      case CustomSnackBarVariant.neutral:
        return AppColors.surface;
      case CustomSnackBarVariant.success:
        return AppColors.success;
      case CustomSnackBarVariant.primary:
        return AppColors.primary;
      case CustomSnackBarVariant.error:
        return AppColors.error;
    }
  }

  static Color _foreground(CustomSnackBarVariant v) {
    switch (v) {
      case CustomSnackBarVariant.neutral:
        return AppColors.textPrimary;
      case CustomSnackBarVariant.success:
      case CustomSnackBarVariant.primary:
      case CustomSnackBarVariant.error:
        return Colors.white;
    }
  }

  static SnackBar _snackBar({
    required String message,
    required CustomSnackBarVariant variant,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final bg = _background(variant);
    final fg = _foreground(variant);
    return SnackBar(
      content: Text(
        message,
        style: AppTextStyles.body.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: duration,
      action:
          (actionLabel != null &&
              actionLabel.isNotEmpty &&
              onAction != null)
          ? SnackBarAction(
              label: actionLabel,
              textColor: fg,
              onPressed: onAction,
            )
          : null,
    );
  }

  /// [context] üzerinden gösterir; [clearCurrent] true ise önceki snackbar kapanır.
  static void show(
    BuildContext context, {
    required String message,
    CustomSnackBarVariant variant = CustomSnackBarVariant.neutral,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
    bool clearCurrent = true,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    showWithMessenger(
      messenger,
      message: message,
      variant: variant,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      clearCurrent: clearCurrent,
    );
  }

  /// Zaten elinizde [ScaffoldMessengerState] varsa (ör. callback içinde).
  static void showWithMessenger(
    ScaffoldMessengerState messenger, {
    required String message,
    CustomSnackBarVariant variant = CustomSnackBarVariant.neutral,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
    bool clearCurrent = true,
  }) {
    if (clearCurrent) messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      _snackBar(
        message: message,
        variant: variant,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
  }
}

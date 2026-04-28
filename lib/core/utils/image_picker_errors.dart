import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Maps [ImagePicker] failures (especially permission denied) to short, actionable text.
String messageForImagePickerError(Object error, ImageSource source) {
  final isCamera = source == ImageSource.camera;

  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final msg = (error.message ?? '').toLowerCase();

    final soundsLikeCamera = code.contains('camera') || msg.contains('camera');
    final soundsLikePhotos = code.contains('photo') ||
        code.contains('gallery') ||
        msg.contains('photo') ||
        msg.contains('library') ||
        msg.contains('gallery');

    final soundsLikeDenied = code.contains('denied') ||
        code == 'permission_denied' ||
        msg.contains('permission denied') ||
        msg.contains('not authorized') ||
        msg.contains('access denied');

    if (isCamera &&
        (soundsLikeCamera || soundsLikeDenied || code == 'permission_denied')) {
      return 'Camera access is turned off. To take a photo, allow camera access in '
          'your device Settings.';
    }
    if (!isCamera &&
        (soundsLikePhotos || soundsLikeDenied || code == 'permission_denied')) {
      return 'Photo library access is turned off. To choose a photo, allow Photos '
          'access in your device Settings.';
    }
  }

  final raw = error.toString().toLowerCase();
  if (raw.contains('permission') &&
      (raw.contains('denied') ||
          raw.contains('not granted') ||
          raw.contains('restricted'))) {
    return isCamera
        ? 'Camera access is turned off. To take a photo, allow camera access in '
            'your device Settings.'
        : 'Photo library access is turned off. To choose a photo, allow Photos '
            'access in your device Settings.';
  }

  return isCamera
      ? 'We could not open the camera. Please try again.'
      : 'We could not open your photo library. Please try again.';
}

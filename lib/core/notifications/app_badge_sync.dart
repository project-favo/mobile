import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

/// Backend `data.badge` değerini (string veya num) uygulama simgesi badge'ine yazar; artırma yapmaz, doğrudan set eder.
Future<void> applyPushBadgeFromMessageData(Map<String, dynamic> data) async {
  if (kIsWeb) return;
  final n = _parseTotalBadgeValue(data['badge']);
  if (n == null) return;
  try {
    if (!await AppBadgePlus.isSupported()) return;
  } catch (_) {
    // Destek sorgulanamazsa yine de set etmeyi dene
  }
  try {
    await AppBadgePlus.updateBadge(n);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('app_badge update failed: $e');
    }
  }
}

int? _parseTotalBadgeValue(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw < 0 ? 0 : raw;
  if (raw is num) {
    final v = raw.toInt();
    return v < 0 ? 0 : v;
  }
  return int.tryParse(raw.toString().trim());
}

/// Logout ve hesap dışı durumlarda: backend senkronu yerel temizleme ile — OS badge 0.
Future<void> clearAppLauncherBadge() async {
  if (kIsWeb) return;
  try {
    if (!await AppBadgePlus.isSupported()) return;
  } catch (_) {}
  try {
    await AppBadgePlus.updateBadge(0);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('app_badge clear failed: $e');
    }
  }
}

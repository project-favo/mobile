import 'dart:developer' as developer;

/// FCM / push-token teşhisi: debug ve release’te konsolda görünür (throttle yok).
void pushTokenLog(
  String message, {
  Object? error,
  int? statusCode,
  Object? responseBody,
  String? fcmTokenPrefix,
}) {
  final b = StringBuffer('[PushToken] $message');
  if (fcmTokenPrefix != null) {
    b.write(' | fcm=…$fcmTokenPrefix');
  }
  if (statusCode != null) b.write(' | http=$statusCode');
  if (responseBody != null) b.write(' | resp=$responseBody');
  if (error != null) b.write(' | error=$error');
  final line = b.toString();
  developer.log(line, name: 'PushToken');
  // avoid_print: kullanıcı talebi — Xcode / logcat’te aynı satır
  // ignore: avoid_print
  print(line);
}

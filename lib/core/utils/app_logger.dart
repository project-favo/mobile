import 'package:flutter/foundation.dart';

/// Merkezi log: [kDebugMode] dışında çıktı yok; production’da davranış değiştirmez.
abstract final class AppLogger {
  AppLogger._();

  static void debug(String message, [Object? error, StackTrace? stack]) {
    if (!kDebugMode) return;
    final buf = StringBuffer('[Favo] $message');
    if (error != null) buf.write(' | $error');
    debugPrint(buf.toString());
    if (stack != null) debugPrint(stack.toString());
  }

  /// Sessiz catch’lerde: sadece debug’da görünür; ürün metni / akışı etkilemez.
  static void warnSilencedError(
    String context,
    Object error, [
    StackTrace? stack,
  ]) {
    debug('swallowed in $context', error, stack);
  }
}

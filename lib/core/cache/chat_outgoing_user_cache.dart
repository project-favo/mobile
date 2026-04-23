import 'dart:typed_data';

/// Sohbet ekranında "benim" satırı için son bilinen profil; [getMe] tekrarını azaltır.
/// Çıkışta [clear] ile boşaltılır.
class ChatOutgoingUserCache {
  ChatOutgoingUserCache._();

  static int? userId;
  static String? avatarUrl;
  static Uint8List? avatarBytes;
  static String? initial;

  static void clear() {
    userId = null;
    avatarUrl = null;
    avatarBytes = null;
    initial = null;
  }
}

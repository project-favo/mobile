import '../../features/auth/data/models/message_dto.dart';

/// Her konuşmanın son mesajlarını memory'de tutar.
/// ChatDetailPage açılışında skeleton göstermeden anında mesajları gösterir.
class MessageListCache {
  MessageListCache._();
  static final MessageListCache instance = MessageListCache._();

  static const int _maxConversations = 20;
  final Map<int, List<MessageDto>> _map = {};

  List<MessageDto>? peek(int conversationId) => _map[conversationId];

  void remember(int conversationId, List<MessageDto> messages) {
    _map[conversationId] = messages;
    // Eski entry'leri temizle
    while (_map.length > _maxConversations) {
      _map.remove(_map.keys.first);
    }
  }
}

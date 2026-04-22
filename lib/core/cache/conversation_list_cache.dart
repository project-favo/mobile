import '../../features/auth/data/models/conversation_dto.dart';

/// Conversation listesini memory'de tutar.
/// ConversationListPage her açılışında cache'den anında gösterir,
/// arka planda refresh eder.
class ConversationListCache {
  ConversationListCache._();
  static final ConversationListCache instance = ConversationListCache._();

  List<ConversationDto>? _conversations;

  List<ConversationDto>? peek() => _conversations;

  void remember(List<ConversationDto> list) {
    _conversations = list;
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/models/conversation_dto.dart';

/// Conversation listesini bellek + disk’te tutar; çıkışta [clear].
class ConversationListCache {
  ConversationListCache._();
  static final ConversationListCache instance = ConversationListCache._();

  static const _prefsKey = 'favo_conversation_list_v1';

  List<ConversationDto>? _conversations;

  List<ConversationDto>? peek() => _conversations;

  void remember(List<ConversationDto> list) {
    _conversations = List<ConversationDto>.from(list);
    // ignore: discarded_futures
    _persistList(list);
  }

  Future<void> _persistList(List<ConversationDto> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      final j = jsonEncode(list.map((e) => e.toJson()).toList());
      if (j.length > 800000) return;
      await p.setString(_prefsKey, j);
    } catch (_) {}
  }

  /// Uygulama açılışında (splash) veya mesaj sekmesinden önce.
  Future<void> restoreFromDisk() async {
    if (_conversations != null && _conversations!.isNotEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .map(
            (e) => ConversationDto.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      _conversations = list;
    } catch (_) {}
  }

  void clear() {
    _conversations = null;
    // ignore: discarded_futures
    _removeDisk();
  }

  Future<void> _removeDisk() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsKey);
  }
}

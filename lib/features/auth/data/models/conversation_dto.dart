class ConversationUserDto {
  final int id;
  final String username;
  final String? profilePhotoUrl;

  ConversationUserDto({
    required this.id,
    required this.username,
    this.profilePhotoUrl,
  });

  factory ConversationUserDto.fromJson(Map<String, dynamic> json) {
    return ConversationUserDto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      profilePhotoUrl: json['profilePhotoUrl']?.toString(),
    );
  }
}

class ConversationDto {
  final int id;
  final ConversationUserDto otherParticipant;
  final String lastMessage;
  final String lastMessageAt;
  final int unreadCount;

  ConversationDto({
    required this.id,
    required this.otherParticipant,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  factory ConversationDto.fromJson(Map<String, dynamic> json) {
    return ConversationDto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      otherParticipant: ConversationUserDto.fromJson(
        json['otherParticipant'] as Map<String, dynamic>? ?? {},
      ),
      lastMessage: json['lastMessage']?.toString() ?? '',
      lastMessageAt: json['lastMessageAt']?.toString() ?? '',
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ConversationPageDto {
  final List<ConversationDto> content;
  final int totalElements;
  final int totalPages;
  final int size;
  final int number;
  final bool first;
  final bool last;
  final bool empty;

  ConversationPageDto({
    required this.content,
    required this.totalElements,
    required this.totalPages,
    required this.size,
    required this.number,
    required this.first,
    required this.last,
    required this.empty,
  });

  factory ConversationPageDto.fromJson(Map<String, dynamic> json) {
    final items = (json['content'] as List? ?? [])
        .map((e) => ConversationDto.fromJson(e as Map<String, dynamic>))
        .toList();

    return ConversationPageDto(
      content: items,
      totalElements: (json['totalElements'] as num?)?.toInt() ?? items.length,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      size: (json['size'] as num?)?.toInt() ?? items.length,
      number: (json['number'] as num?)?.toInt() ?? 0,
      first: json['first'] as bool? ?? true,
      last: json['last'] as bool? ?? true,
      empty: json['empty'] as bool? ?? items.isEmpty,
    );
  }
}


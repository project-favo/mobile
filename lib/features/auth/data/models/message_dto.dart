class MessageDto {
  final int id;
  final int conversationId;
  final int senderId;
  final String senderUsername;
  final String content;
  final String createdAt;
  final bool isRead;

  MessageDto({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderUsername,
    required this.content,
    required this.createdAt,
    required this.isRead,
  });

  factory MessageDto.fromJson(Map<String, dynamic> json) {
    return MessageDto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
      senderId: (json['senderId'] as num?)?.toInt() ?? 0,
      senderUsername: json['senderUsername']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      isRead: json['isRead'] as bool? ?? false,
    );
  }
}

class MessagePageDto {
  final List<MessageDto> content;
  final int totalElements;
  final int totalPages;
  final int size;
  final int number;
  final bool first;
  final bool last;
  final bool empty;

  MessagePageDto({
    required this.content,
    required this.totalElements,
    required this.totalPages,
    required this.size,
    required this.number,
    required this.first,
    required this.last,
    required this.empty,
  });

  factory MessagePageDto.fromJson(Map<String, dynamic> json) {
    final items = (json['content'] as List? ?? [])
        .map((e) => MessageDto.fromJson(e as Map<String, dynamic>))
        .toList();

    return MessagePageDto(
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


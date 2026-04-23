import '../../../../core/utils/user_account_flags.dart';

class ConversationUserDto {
  final int id;
  final String username;
  final String? profilePhotoUrl;
  /// Bazı API’ler base64 döner (UserResponseDto ile uyumlu).
  final String? profilePhotoData;
  /// Liste / sohbet özetinde [isActive] vb. sinyaller varsa vitrin dışı kabul edilir.
  final bool isAccountInactive;

  ConversationUserDto({
    required this.id,
    required this.username,
    this.profilePhotoUrl,
    this.profilePhotoData,
    this.isAccountInactive = false,
  });

  bool get hasAvatarVisual {
    final u = profilePhotoUrl?.trim();
    if (u != null && u.isNotEmpty) return true;
    final d = profilePhotoData?.trim();
    return d != null && d.isNotEmpty;
  }

  factory ConversationUserDto.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['userId'] ?? json['participantId'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    // UserResponseDto: userName, profileImageUrl
    final username = json['userName']?.toString() ??
        json['username']?.toString() ??
        '';
    final photo = json['profileImageUrl']?.toString() ??
        json['profilePhotoUrl']?.toString() ??
        json['avatarUrl']?.toString() ??
        json['photoUrl']?.toString() ??
        json['imageUrl']?.toString();
    final data = json['profilePhotoData']?.toString() ??
        json['profilePhoto']?.toString();
    return ConversationUserDto(
      id: id,
      username: username,
      profilePhotoUrl: photo,
      profilePhotoData: data,
      isAccountInactive: json['isAccountInactive'] == true ||
          isUserAccountInactiveInMap(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userName': username,
      'username': username,
      'profilePhotoUrl': profilePhotoUrl,
      'profilePhotoData': profilePhotoData,
      'isAccountInactive': isAccountInactive,
    };
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
    final rawOp = json['otherParticipant'] ??
        json['participant'] ??
        json['otherUser'] ??
        json['user'];
    final opMap = rawOp is Map<String, dynamic>
        ? rawOp
        : <String, dynamic>{};
    return ConversationDto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      otherParticipant: ConversationUserDto.fromJson(opMap),
      lastMessage: json['lastMessage']?.toString() ?? '',
      lastMessageAt: json['lastMessageAt']?.toString() ?? '',
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'otherParticipant': otherParticipant.toJson(),
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt,
      'unreadCount': unreadCount,
    };
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


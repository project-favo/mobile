class FriendsFeedItemDto {
  const FriendsFeedItemDto({
    required this.id,
    required this.type,
    required this.actorUserId,
    required this.actorUserName,
    this.actorDisplayName,
    this.actorProfilePhotoUrl,
    this.productId,
    this.productName,
    this.productImageUrl,
    this.reviewId,
    this.reviewTitle,
    this.reviewContent,
    this.createdAt,
  });

  final String id;
  final String type;
  final String actorUserId;
  final String actorUserName;
  final String? actorDisplayName;
  final String? actorProfilePhotoUrl;
  final String? productId;
  final String? productName;
  final String? productImageUrl;
  final String? reviewId;
  final String? reviewTitle;
  final String? reviewContent;
  final DateTime? createdAt;

  factory FriendsFeedItemDto.fromJson(Map<String, dynamic> json) {
    String firstNonEmpty(List<String> keys) {
      for (final k in keys) {
        final raw = json[k];
        if (raw == null) continue;
        final val = raw.toString().trim();
        if (val.isNotEmpty) return val;
      }
      return '';
    }

    String? nullableFirstNonEmpty(List<String> keys) {
      final v = firstNonEmpty(keys);
      return v.isEmpty ? null : v;
    }

    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is String) return DateTime.tryParse(raw);
      if (raw is List && raw.isNotEmpty) {
        int nAt(int i, [int fallback = 0]) {
          if (i >= raw.length) return fallback;
          final e = raw[i];
          if (e is num) return e.toInt();
          return int.tryParse(e.toString()) ?? fallback;
        }
        try {
          return DateTime(
            nAt(0, DateTime.now().year),
            nAt(1, 1),
            nAt(2, 1),
            nAt(3),
            nAt(4),
            nAt(5),
          );
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final itemId = firstNonEmpty([
      'id',
      'eventId',
      'activityId',
      'reviewId',
      'productId',
    ]);

    return FriendsFeedItemDto(
      id: itemId,
      type: firstNonEmpty(['type', 'activityType']),
      actorUserId: firstNonEmpty(['actorUserId', 'userId', 'actorId']),
      actorUserName: firstNonEmpty(['actorUserName', 'userName', 'username']),
      actorDisplayName: nullableFirstNonEmpty(['actorDisplayName', 'displayName']),
      actorProfilePhotoUrl: nullableFirstNonEmpty([
        'actorProfilePhotoUrl',
        'profilePhotoUrl',
      ]),
      productId: nullableFirstNonEmpty(['productId']),
      productName: nullableFirstNonEmpty(['productName']),
      productImageUrl: nullableFirstNonEmpty(['productImageUrl']),
      reviewId: nullableFirstNonEmpty(['reviewId']),
      reviewTitle: nullableFirstNonEmpty(['reviewTitle', 'title']),
      reviewContent: nullableFirstNonEmpty(['reviewContent', 'reviewText', 'body']),
      createdAt: parseDate(
        json['createdAt'] ?? json['timestamp'] ?? json['eventTime'],
      ),
    );
  }
}

class FriendsFeedPageDto {
  const FriendsFeedPageDto({
    required this.content,
    required this.totalElements,
    required this.totalPages,
    required this.size,
    required this.number,
  });

  final List<FriendsFeedItemDto> content;
  final int totalElements;
  final int totalPages;
  final int size;
  final int number;

  factory FriendsFeedPageDto.fromJson(Map<String, dynamic> json) {
    final list = (json['content'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => FriendsFeedItemDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return FriendsFeedPageDto(
      content: list,
      totalElements: (json['totalElements'] as num?)?.toInt() ?? list.length,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      size: (json['size'] as num?)?.toInt() ?? 20,
      number: (json['number'] as num?)?.toInt() ?? 0,
    );
  }
}

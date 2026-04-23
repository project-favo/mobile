import 'dart:convert';

import '../../../../core/utils/app_datetime.dart';
import '../../../../core/utils/product_listing_flags.dart';
import '../../../../core/utils/user_account_flags.dart';

/// Spring bazen [year, month, day, hour, minute, second, nano] dizisi döndürür.
DateTime? parseFlexibleDateTime(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    return parseBackendDateTimeToLocal(value);
  }
  if (value is List && value.isNotEmpty) {
    int nAt(int i) {
      if (i >= value.length) return 0;
      final e = value[i];
      if (e is num) return e.toInt();
      return int.tryParse(e.toString()) ?? 0;
    }

    final y = nAt(0);
    final mo = value.length > 1 ? nAt(1) : 1;
    final d = value.length > 2 ? nAt(2) : 1;
    final h = value.length > 3 ? nAt(3) : 0;
    final mi = value.length > 4 ? nAt(4) : 0;
    final s = value.length > 5 ? nAt(5) : 0;
    try {
      return DateTime.utc(y, mo, d, h, mi, s).toLocal();
    } catch (_) {
      return null;
    }
  }
  return null;
}

String notificationIdToString(dynamic raw) {
  if (raw == null) return '';
  if (raw is String) return raw;
  return raw.toString();
}

/// Bildirimi tetikleyen kullanıcı özeti (`GET /api/notifications`, WebSocket).
class NotificationActorDto {
  final int id;
  final String? userName;
  final String profileImageUrl;
  /// [isUserAccountInactiveInMap] — yok/ pasif actor; listede gizle.
  final bool isAccountInactive;

  const NotificationActorDto({
    required this.id,
    this.userName,
    required this.profileImageUrl,
    this.isAccountInactive = false,
  });

  factory NotificationActorDto.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    return NotificationActorDto(
      id: id,
      userName: json['userName']?.toString(),
      profileImageUrl: json['profileImageUrl']?.toString() ?? '',
      isAccountInactive: json['isAccountInactive'] == true ||
          isUserAccountInactiveInMap(json) ||
          isUserSuspendedSignalInMap(json),
    );
  }
}

/// Product summary attached by activity notification endpoint.
class NotificationProductDto {
  final int id;
  final String name;
  final String? imageURL;
  /// [isProductDataNotListedInMap] — vitrin dışı / pasif; listede gizle.
  final bool isProductNotListed;

  const NotificationProductDto({
    required this.id,
    required this.name,
    this.imageURL,
    this.isProductNotListed = false,
  });

  factory NotificationProductDto.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final rawImage = json['imageURL']?.toString().trim();
    var notListed = isProductDataNotListedInMap(json);
    if (!notListed && (rawImage == null || rawImage.isEmpty)) {
      notListed = isNotListedImpliedByEmptyProductImage(rawImage);
    }
    return NotificationProductDto(
      id: id,
      name: json['name']?.toString() ?? '',
      imageURL: (rawImage == null || rawImage.isEmpty) ? null : rawImage,
      isProductNotListed: notListed,
    );
  }
}

class NotificationDto {
  final String id;
  final String type;
  final NotificationActorDto? actor;
  final NotificationProductDto? product;
  final String? actorDisplayName;
  final String title;
  final String? body;
  final String? payloadJson;
  final DateTime? createdAt;
  final DateTime? readAt;

  NotificationDto({
    required this.id,
    required this.type,
    this.actor,
    this.product,
    this.actorDisplayName,
    required this.title,
    this.body,
    this.payloadJson,
    this.createdAt,
    this.readAt,
  });

  bool get isUnread => readAt == null;

  /// [getUserById] ile “profilde açılamıyor” kontrolü; [actor] yoksa [payloadJson]’dan id okur.
  int? get resolvedUserIdForVisibilityCheck {
    final a = actor;
    if (a != null && a.id > 0) return a.id;
    final raw = payloadJson;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final d = jsonDecode(raw);
      if (d is! Map<String, dynamic>) return null;
      // [userId] çoğunlukla bildirimi **alan** kullanıcıdır; takip eden/aktör değil — dahil etme.
      for (final k in [
        'actorUserId',
        'followerUserId',
        'initiatorId',
        'performerId',
        'sourceUserId',
        'fromUserId',
      ]) {
        final v = d[k];
        if (v is num) {
          final n = v.toInt();
          if (n > 0) return n;
        }
        if (v is String) {
          final n = int.tryParse(v.trim());
          if (n != null && n > 0) return n;
        }
      }
    } catch (_) {}
    return null;
  }

  NotificationDto copyWith({
    String? id,
    String? type,
    NotificationActorDto? actor,
    NotificationProductDto? product,
    String? actorDisplayName,
    String? title,
    String? body,
    String? payloadJson,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return NotificationDto(
      id: id ?? this.id,
      type: type ?? this.type,
      actor: actor ?? this.actor,
      product: product ?? this.product,
      actorDisplayName: actorDisplayName ?? this.actorDisplayName,
      title: title ?? this.title,
      body: body ?? this.body,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    NotificationActorDto? actor;
    final rawActor = json['actor'] ?? json['user'] ?? json['fromUser'];
    if (rawActor is Map<String, dynamic>) {
      // Kök seviyedeki [isActive] / [read] vb. asla [actor] ile birleştirilmez: çoğunlukla
      // **bildirim satırının** durumudur; tüm satırları “pasif kullanıcı” zannedip eler.
      final merged = Map<String, dynamic>.from(rawActor);
      for (final k in ['actorIsActive', 'initiatorIsActive', 'performerIsActive']) {
        if (json[k] != null) {
          merged.putIfAbsent('isActive', () => json[k]);
          break;
        }
      }
      if (json['actorAccountInactive'] != null) {
        merged.putIfAbsent('isAccountInactive', () => json['actorAccountInactive']);
      }
      actor = NotificationActorDto.fromJson(merged);
    }
    NotificationProductDto? product;
    final rawProduct = json['product'];
    if (rawProduct is Map<String, dynamic>) {
      product = NotificationProductDto.fromJson(rawProduct);
    }
    if (product == null) {
      final pPayload = json['payload'];
      if (pPayload is Map<String, dynamic>) {
        final sub = pPayload['product'];
        if (sub is Map<String, dynamic>) {
          product = NotificationProductDto.fromJson(sub);
        }
      }
    }
    if (product == null) {
      final rawPj = json['payloadJson'];
      if (rawPj != null) {
        try {
          final decoded = jsonDecode(rawPj.toString());
          if (decoded is Map<String, dynamic>) {
            final sub = decoded['product'];
            if (sub is Map<String, dynamic>) {
              product = NotificationProductDto.fromJson(sub);
            }
          }
        } catch (_) {}
      }
    }

    return NotificationDto(
      id: notificationIdToString(json['id']),
      type: json['type']?.toString() ?? '',
      actor: actor,
      product: product,
      actorDisplayName: json['actorDisplayName']?.toString(),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString(),
      payloadJson: json['payloadJson']?.toString(),
      createdAt: parseFlexibleDateTime(json['createdAt']),
      readAt: parseFlexibleDateTime(json['readAt']),
    );
  }
}

class NotificationPageDto {
  final List<NotificationDto> content;
  final int totalElements;
  final int totalPages;
  final int size;
  final int number;
  final bool first;
  final bool last;
  final bool empty;

  NotificationPageDto({
    required this.content,
    required this.totalElements,
    required this.totalPages,
    required this.size,
    required this.number,
    required this.first,
    required this.last,
    required this.empty,
  });

  factory NotificationPageDto.fromJson(Map<String, dynamic> json) {
    final items = (json['content'] as List? ?? [])
        .map((e) => NotificationDto.fromJson(e as Map<String, dynamic>))
        .toList();

    return NotificationPageDto(
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

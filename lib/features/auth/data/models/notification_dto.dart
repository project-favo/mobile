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

  factory NotificationProductDto.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? notificationRow,
  }) {
    final rawId = json['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final rawImage = json['imageURL']?.toString().trim();
    var notListed = isProductDataNotListedInMap(json);
    if (!notListed && notificationRow != null) {
      notListed = isProductDataNotListedInMap(notificationRow) ||
          isProductNotListedFromJsonMap(notificationRow);
    }
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
      product = NotificationProductDto.fromJson(
        rawProduct,
        notificationRow: json,
      );
    }
    if (product == null) {
      final pPayload = json['payload'];
      if (pPayload is Map<String, dynamic>) {
        final sub = pPayload['product'];
        if (sub is Map<String, dynamic>) {
          product = NotificationProductDto.fromJson(
            sub,
            notificationRow: json,
          );
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
              product = NotificationProductDto.fromJson(
                sub,
                notificationRow: json,
              );
            }
          }
        } catch (_) {}
      }
    }

    final mergedPayloadJson = _mergeNotificationPayloadJsonFields(json);

    return NotificationDto(
      id: notificationIdToString(json['id']),
      type: json['type']?.toString() ?? '',
      actor: actor,
      product: product,
      actorDisplayName: json['actorDisplayName']?.toString(),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString(),
      payloadJson: mergedPayloadJson,
      createdAt: parseFlexibleDateTime(json['createdAt']),
      readAt: parseFlexibleDateTime(json['readAt']),
    );
  }
}

/// [payloadJson] string + kök [payload] / [data] map’lerini tek JSON metninde birleştirir
/// (reviewId yalnızca [payload] içinde geldiğinde [notificationReviewIdKey] kaçırmasın).
String? _mergeNotificationPayloadJsonFields(Map<String, dynamic> json) {
  Map<String, dynamic>? merged;
  void mergeIn(Map<String, dynamic> m) {
    merged = merged == null ? Map<String, dynamic>.from(m) : {...merged!, ...m};
  }

  final rawPj = json['payloadJson'];
  if (rawPj != null && rawPj.toString().trim().isNotEmpty) {
    try {
      final d = jsonDecode(rawPj.toString());
      if (d is Map<String, dynamic>) {
        mergeIn(d);
      }
    } catch (_) {}
  }
  for (final key in [
    'payload',
    'data',
    'metadata',
    'context',
    'target',
    'entity',
    'details',
    'extras',
    'resource',
    'notificationPayload',
  ]) {
    final v = json[key];
    if (v is Map<String, dynamic>) {
      mergeIn(v);
    }
  }
  if (merged != null && merged!.isNotEmpty) {
    return jsonEncode(merged);
  }
  return rawPj?.toString();
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

/// "X liked your review" satırı mı? (ürün/review kimliği olmadan vitrin kontrolü yapılamaz → elenebilir.)
bool notificationIsLikedYourReviewRow(NotificationDto n) {
  final t = n.type.toUpperCase();
  final body = '${n.title} ${n.body ?? ''}'.toLowerCase();
  if (body.contains('liked your review') || body.contains('like your review')) {
    return true;
  }
  if (t.contains('LIKE') && t.contains('REVIEW')) return true;
  if (body.contains('your') && body.contains('review') && body.contains('liked')) {
    return true;
  }
  return false;
}

/// Başka kullanıcıların ürüne review bırakmasına dair bildirim türü mü (like/reply vb. değil).
bool notificationTypeIsOthersProductReviewPost(String type) {
  final t = type.toUpperCase();
  if (!t.contains('REVIEW')) return false;
  if (t.contains('LIKE')) return false;
  return true;
}

String? _productIdFromUrlString(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final u = s.trim();
  for (final re in [
    RegExp(r'/api/products/([^/?#]+)'),
    RegExp(r'/products/([^/?#]+)'),
    RegExp(r'[?&]productId=([^&]+)'),
  ]) {
    final m = re.firstMatch(u);
    final g = m?.group(1)?.trim();
    if (g != null && g.isNotEmpty) return g;
  }
  return null;
}

String? _deepFindProductIdInJson(dynamic node, {int depth = 0}) {
  if (depth > 10) return null;
  const keyHints = <String>{
    'productid',
    'product_id',
    'targetproductid',
    'catalogproductid',
    'listedproductid',
    'itemproductid',
  };
  if (node is Map<String, dynamic>) {
    for (final e in node.entries) {
      final lk = e.key.toString().toLowerCase().replaceAll('-', '_');
      if (keyHints.contains(lk) ||
          lk.endsWith('_product_id') ||
          lk.endsWith('product_id')) {
        final s = e.value?.toString().trim() ?? '';
        if (s.isNotEmpty) return s;
      }
      if (lk.contains('image') ||
          lk.contains('thumb') ||
          lk.contains('photo') ||
          lk.endsWith('url')) {
        final fromUrl = _productIdFromUrlString(e.value?.toString());
        if (fromUrl != null) return fromUrl;
      }
    }
    for (final nk in ['product', 'targetProduct', 'catalogProduct']) {
      final sub = node[nk];
      if (sub is Map<String, dynamic>) {
        final id = sub['id'] ?? sub['productId'];
        if (id is num && id > 0) return id.toInt().toString();
        final idS = id?.toString().trim();
        if (idS != null && idS.isNotEmpty) return idS;
      }
    }
    for (final e in node.entries) {
      final inner = _deepFindProductIdInJson(e.value, depth: depth + 1);
      if (inner != null) return inner;
    }
  } else if (node is List) {
    for (final item in node) {
      final inner = _deepFindProductIdInJson(item, depth: depth + 1);
      if (inner != null) return inner;
    }
  }
  return null;
}

/// Ürün kimliği: gömülü [product] veya [payloadJson] içinden (derin tarama + URL).
String? notificationProductIdKey(NotificationDto n) {
  final p = n.product;
  if (p != null && p.id > 0) return p.id.toString();
  final raw = n.payloadJson;
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final d = jsonDecode(raw);
    if (d is! Map<String, dynamic>) return null;
    for (final k in ['productId', 'product_id']) {
      final v = d[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    final prod = d['product'];
    if (prod is Map<String, dynamic>) {
      final id = prod['id'];
      if (id is num && id > 0) return id.toInt().toString();
      final idS = id?.toString().trim();
      if (idS != null && idS.isNotEmpty) return idS;
    }
    for (final rk in ['review', 'targetReview', 'likedReview', 'reviewDto']) {
      final rev = d[rk];
      if (rev is! Map<String, dynamic>) continue;
      for (final k in ['productId', 'product_id']) {
        final v = rev[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      final rp = rev['product'];
      if (rp is Map<String, dynamic>) {
        final id = rp['id'];
        if (id is num && id > 0) return id.toInt().toString();
        final idS = id?.toString().trim();
        if (idS != null && idS.isNotEmpty) return idS;
      }
    }
    final deep = _deepFindProductIdInJson(d);
    if (deep != null && deep.isNotEmpty) return deep;
    if (p != null) {
      final fromImg = _productIdFromUrlString(p.imageURL);
      if (fromImg != null) return fromImg;
    }
  } catch (_) {}
  return null;
}

String? _reviewIdFromPayloadMap(Map<String, dynamic> d) {
  for (final k in [
    'reviewId',
    'review_id',
    'targetReviewId',
    'likedReviewId',
    'sourceReviewId',
  ]) {
    final v = d[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  for (final rk in ['review', 'targetReview', 'likedReview', 'reviewDto']) {
    final rev = d[rk];
    if (rev is! Map<String, dynamic>) continue;
    final id = rev['id'] ?? rev['reviewId'];
    if (id == null) continue;
    final s = id.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

String? _deepFindReviewIdInJson(dynamic node, {int depth = 0}) {
  if (depth > 10) return null;
  const keyHints = <String>{
    'reviewid',
    'review_id',
    'targetreviewid',
    'likedreviewid',
    'sourcereviewid',
    'reviewreferenceid',
    'parentreviewid',
    'commentreviewid',
  };
  if (node is Map<String, dynamic>) {
    for (final e in node.entries) {
      final lk = e.key.toString().toLowerCase().replaceAll('-', '_');
      if (keyHints.contains(lk) ||
          lk.endsWith('_review_id') ||
          lk.endsWith('review_id')) {
        final s = e.value?.toString().trim() ?? '';
        if (s.isNotEmpty) return s;
      }
    }
    for (final e in node.entries) {
      final inner = _deepFindReviewIdInJson(e.value, depth: depth + 1);
      if (inner != null) return inner;
    }
  } else if (node is List) {
    for (final item in node) {
      final inner = _deepFindReviewIdInJson(item, depth: depth + 1);
      if (inner != null) return inner;
    }
  }
  return null;
}

/// [payloadJson] (+ birleştirilmiş kök payload) içinden review kimliği.
String? notificationReviewIdKey(NotificationDto n) {
  final raw = n.payloadJson;
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final d = jsonDecode(raw);
    if (d is! Map<String, dynamic>) return null;
    return _reviewIdFromPayloadMap(d) ?? _deepFindReviewIdInJson(d);
  } catch (_) {}
  return null;
}

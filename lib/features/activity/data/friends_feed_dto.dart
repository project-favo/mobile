import 'package:favo_mobile/core/utils/product_listing_flags.dart';
import 'package:favo_mobile/core/utils/user_account_flags.dart';
import 'package:favo_mobile/core/utils/app_datetime.dart';

bool _userMapLooksDeactivated(Map<String, dynamic> m) {
  final st = (m['status'] ?? m['accountStatus'] ?? '')
      .toString()
      .toLowerCase();
  if (st == 'deactivated' || st == 'inactive' || st == 'suspended') {
    return true;
  }
  if (m['isAccountDeactivated'] is bool && (m['isAccountDeactivated'] as bool)) {
    return true;
  }
  if (m['active'] is bool && !(m['active'] as bool)) return true;
  if (m['isActive'] is bool && !(m['isActive'] as bool)) return true;
  if (m['enabled'] is bool && !(m['enabled'] as bool)) return true;
  return false;
}

bool _actorDeactivatedFromFeedJson(Map<String, dynamic> json) {
  final a = json['actorAccountDeactivated'] ?? json['actorDeactivated'];
  if (a is bool) return a;
  final actor = json['actor'] ?? json['user'];
  if (actor is Map) {
    if (_userMapLooksDeactivated(Map<String, dynamic>.from(actor))) {
      return true;
    }
  }
  for (final k in ['actorStatus', 'userStatus', 'actorAccountStatus']) {
    final v = json[k]?.toString().toLowerCase() ?? '';
    if (v == 'deactivated' || v == 'inactive' || v == 'suspended') {
      return true;
    }
  }
  if (json['actorActive'] is bool && !(json['actorActive'] as bool)) {
    return true;
  }
  return false;
}

Map<String, dynamic>? _asStringKeyedMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

String _firstNonEmptyIn(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final raw = m[k];
    if (raw == null) continue;
    final val = raw.toString().trim();
    if (val.isNotEmpty) return val;
  }
  return '';
}

String? _nullableFirstNonEmptyIn(Map<String, dynamic> m, List<String> keys) {
  final v = _firstNonEmptyIn(m, keys);
  return v.isEmpty ? null : v;
}

/// Kök [userId] çoğu API’de bildirim/hedef kullanıcıdır; gerçek aktörü [actor] vb. iç içe nesnelerden oku.
String _resolveFriendsFeedActorUserId(Map<String, dynamic> json) {
  final env = _firstNonEmptyIn(json, [
    'actorUserId',
    'actorId',
    'performerId',
    'fromUserId',
    'initiatorId',
    'sourceUserId',
  ]);
  if (env.isNotEmpty) return env;

  for (final nk in _nestedKeysForFriendsFeedActor()) {
    final nested = _asStringKeyedMap(json[nk]);
    if (nested == null) continue;
    final id = _firstNonEmptyIn(nested, [
      'actorUserId',
      'userId',
      'id',
      'firebaseUid',
      'uid',
      'actorId',
    ]);
    if (id.isNotEmpty) return id;
  }

  return _firstNonEmptyIn(json, ['userId']);
}

String _resolveFriendsFeedActorUserName(Map<String, dynamic> json) {
  final env = _firstNonEmptyIn(json, ['actorUserName', 'actorName']);
  if (env.isNotEmpty) return env;

  for (final nk in _nestedKeysForFriendsFeedActor()) {
    final nested = _asStringKeyedMap(json[nk]);
    if (nested == null) continue;
    final name = _firstNonEmptyIn(nested, [
      'username',
      'userName',
      'name',
      'displayName',
      'fullName',
    ]);
    if (name.isNotEmpty) return name;
  }

  return _firstNonEmptyIn(json, ['userName', 'username']);
}

String? _resolveFriendsFeedActorDisplayName(Map<String, dynamic> json) {
  final env = _nullableFirstNonEmptyIn(json, ['actorDisplayName']);
  if (env != null) return env;

  for (final nk in _nestedKeysForFriendsFeedActor()) {
    final nested = _asStringKeyedMap(json[nk]);
    if (nested == null) continue;
    final d = _nullableFirstNonEmptyIn(nested, [
      'displayName',
      'fullName',
      'name',
    ]);
    if (d != null) return d;
  }

  return _nullableFirstNonEmptyIn(json, ['displayName']);
}

String? _resolveFriendsFeedActorProfilePhotoUrl(Map<String, dynamic> json) {
  final env = _nullableFirstNonEmptyIn(json, [
    'actorProfilePhotoUrl',
    'actorAvatarUrl',
  ]);
  if (env != null) return env;

  for (final nk in _nestedKeysForFriendsFeedActor()) {
    final nested = _asStringKeyedMap(json[nk]);
    if (nested == null) continue;
    final u = _nullableFirstNonEmptyIn(nested, [
      'profilePhotoUrl',
      'profilePhotoURL',
      'avatarUrl',
      'avatarURL',
      'profileImageUrl',
      'photoUrl',
      'imageUrl',
      'picture',
    ]);
    if (u != null) return u;
  }

  return _nullableFirstNonEmptyIn(json, [
    'profilePhotoUrl',
    'profilePhotoURL',
  ]);
}

List<String> _nestedKeysForFriendsFeedActor() => const [
      'actor',
      'actorUser',
      'fromUser',
      'performedBy',
      'user',
    ];

class FriendsFeedItemDto {
  FriendsFeedItemDto({
    required this.id,
    required this.type,
    required this.actorUserId,
    required this.actorUserName,
    this.isActorAccountDeactivated = false,
    this.actorDisplayName,
    this.actorProfilePhotoUrl,
    this.productId,
    this.productName,
    this.productImageUrl,
    this.reviewId,
    this.reviewTitle,
    this.reviewContent,
    this.createdAt,
    this.isActorUserInactive = false,
    this.isProductSnapshotNotListed = false,
  });

  final String id;
  final String type;
  final String actorUserId;
  final String actorUserName;
  /// API: hesabı kapatılmış aktör — feed’de gösterme.
  final bool isActorAccountDeactivated;
  final String? actorDisplayName;
  final String? actorProfilePhotoUrl;
  final String? productId;
  final String? productName;
  final String? productImageUrl;
  final String? reviewId;
  final String? reviewTitle;
  final String? reviewContent;
  final DateTime? createdAt;
  /// [actor] / [user] gövdeleri veya kök JSON’daki isActive sinyali.
  final bool isActorUserInactive;
  /// Satır bir ürüne atıf yapıyorsa, vitrin dışı ürün anlık görüntüsü (bayrak + nested [product]).
  final bool isProductSnapshotNotListed;

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
      if (raw is String) return parseBackendDateTimeToLocal(raw);
      if (raw is List && raw.isNotEmpty) {
        int nAt(int i, [int fallback = 0]) {
          if (i >= raw.length) return fallback;
          final e = raw[i];
          if (e is num) return e.toInt();
          return int.tryParse(e.toString()) ?? fallback;
        }
        try {
          return DateTime.utc(
            nAt(0, DateTime.now().year),
            nAt(1, 1),
            nAt(2, 1),
            nAt(3),
            nAt(4),
            nAt(5),
          ).toLocal();
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

    String? productIdFromNested(String nk) {
      final nested = _asStringKeyedMap(json[nk]);
      if (nested == null) return null;
      final direct = _nullableFirstNonEmptyIn(nested, [
        'productId',
        'product_id',
      ]);
      if (direct != null) return direct;
      final nestedId = _nullableFirstNonEmptyIn(nested, ['id']);
      if (nestedId != null &&
          (nk == 'product' ||
              nk == 'targetProduct' ||
              nk == 'item' ||
              nk == 'event')) {
        return nestedId;
      }
      final prod = _asStringKeyedMap(nested['product']);
      if (prod != null) {
        final fromProd = _nullableFirstNonEmptyIn(prod, [
          'id',
          'productId',
          'product_id',
        ]);
        if (fromProd != null) return fromProd;
      }
      return null;
    }

    var productIdV = nullableFirstNonEmpty([
      'productId',
      'product_id',
      'targetProductId',
      'itemId',
    ]);
    productIdV ??= productIdFromNested('product');
    productIdV ??= productIdFromNested('targetProduct');
    productIdV ??= productIdFromNested('item');
    // Yorum satırında kök productId boş; iç içe review/payload üzerinden ürün id.
    for (final nk in ['review', 'payload', 'data', 'content', 'event']) {
      productIdV ??= productIdFromNested(nk);
    }
    final productNameV = nullableFirstNonEmpty(['productName']);
    final productImageV = nullableFirstNonEmpty(['productImageUrl', 'productImageURL']);

    final actorInactive = isUserAccountInactiveInMap(_mergedActorJsonForFeed(json));
    var productNotListed = false;
    if (productIdV != null && productIdV.trim().isNotEmpty) {
      productNotListed = isProductDataNotListedInMap(
        _mergedProductJsonForFeed(
          json,
          productId: productIdV,
          productName: productNameV,
          productImageUrl: productImageV,
        ),
      );
    }
    productNotListed =
        productNotListed || isProductNotListedFromJsonMap(json);

    return FriendsFeedItemDto(
      id: itemId,
      type: firstNonEmpty(['type', 'activityType']),
      actorUserId: _resolveFriendsFeedActorUserId(json),
      actorUserName: _resolveFriendsFeedActorUserName(json),
      isActorAccountDeactivated: _actorDeactivatedFromFeedJson(json),
      actorDisplayName: _resolveFriendsFeedActorDisplayName(json),
      actorProfilePhotoUrl: _resolveFriendsFeedActorProfilePhotoUrl(json),
      productId: productIdV,
      productName: productNameV,
      productImageUrl: productImageV,
      reviewId: nullableFirstNonEmpty(['reviewId']),
      reviewTitle: nullableFirstNonEmpty(['reviewTitle', 'title']),
      reviewContent: nullableFirstNonEmpty(['reviewContent', 'reviewText', 'body']),
      createdAt: parseDate(
        json['createdAt'] ?? json['timestamp'] ?? json['eventTime'],
      ),
      isActorUserInactive: actorInactive,
      isProductSnapshotNotListed: productNotListed,
    );
  }
}

Map<String, dynamic> _mergedActorJsonForFeed(Map<String, dynamic> json) {
  final m = Map<String, dynamic>.from(json);
  for (final k in ['actor', 'user', 'actorUser', 'fromUser', 'performedBy']) {
    final v = json[k];
    if (v is Map) {
      m.addAll(Map<String, dynamic>.from(v));
    }
  }
  return m;
}

Map<String, dynamic> _mergedProductJsonForFeed(
  Map<String, dynamic> json, {
  required String? productId,
  required String? productName,
  required String? productImageUrl,
}) {
  final m = <String, dynamic>{
    'id': productId,
    'name': productName,
    'imageURL': productImageUrl ?? '',
    'productName': productName,
    'productId': productId,
  };
  for (final k in ['product', 'targetProduct', 'item']) {
    final v = json[k];
    if (v is Map) {
      m.addAll(Map<String, dynamic>.from(v));
    }
  }
  for (final e in json.entries) {
    final key = e.key;
    if (key.startsWith('product') &&
        key != 'productId' &&
        key != 'productName' &&
        key != 'productImageUrl' &&
        key != 'productImageURL') {
      m[key] = e.value;
    }
  }
  return m;
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

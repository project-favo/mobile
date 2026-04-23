class UserResponseDto {
  final String id;
  final String email;
  final String userName;
  final String? name;
  final String? surname;
  final String? birthdate;
  final String? profileImageUrl;
  final String? profilePhotoData;
  final String? profilePhotoMimeType;
  // null → legacy (treat as verified), false → not verified, true → verified
  final bool? emailVerified;

  /// Backend hesabı kapatıldıysa true (feed/önbellekte hareket göstermemek için).
  final bool isAccountDeactivated;

  UserResponseDto({
    required this.id,
    required this.email,
    required this.userName,
    this.name,
    this.surname,
    this.birthdate,
    this.profileImageUrl,
    this.profilePhotoData,
    this.profilePhotoMimeType,
    this.emailVerified,
    this.isAccountDeactivated = false,
  });

  /// Backend: null → legacy (verified), false → not verified, true → verified
  bool get isEmailVerified => emailVerified != false;

  /// URL veya base64 ile doldurulmuş görsel var mı (mesajlaşma / profil).
  bool get hasProfileAvatarVisual {
    final u = profileImageUrl?.trim();
    if (u != null && u.isNotEmpty) return true;
    final d = profilePhotoData?.trim();
    return d != null && d.isNotEmpty;
  }

  /// Profil fotoğrafı kaldırıldığında backend bazen eski URL/base64 döndürebilir; UI’da anında placeholder için.
  UserResponseDto withProfileMediaCleared() {
    return UserResponseDto(
      id: id,
      email: email,
      userName: userName,
      name: name,
      surname: surname,
      birthdate: birthdate,
      profileImageUrl: null,
      profilePhotoData: null,
      profilePhotoMimeType: null,
      emailVerified: emailVerified,
      isAccountDeactivated: isAccountDeactivated,
    );
  }

  /// Sadece görünen kullanıcı adı (büyük/küçük harf) yerel güncelleme — sunucu aynı kalırsa UI senkronu için.
  UserResponseDto withUserName(String newUserName) {
    return UserResponseDto(
      id: id,
      email: email,
      userName: newUserName,
      name: name,
      surname: surname,
      birthdate: birthdate,
      profileImageUrl: profileImageUrl,
      profilePhotoData: profilePhotoData,
      profilePhotoMimeType: profilePhotoMimeType,
      emailVerified: emailVerified,
      isAccountDeactivated: isAccountDeactivated,
    );
  }

  /// `/api/auth/me` seyrek dönerse; `/api/users/{id}` vb. ile gelen avatarı birleştirir.
  UserResponseDto withFilledAvatarFrom(UserResponseDto? other) {
    if (other == null) return this;
    if (hasProfileAvatarVisual) return this;
    if (!other.hasProfileAvatarVisual) return this;
    return UserResponseDto(
      id: id,
      email: email,
      userName: userName,
      name: name,
      surname: surname,
      birthdate: birthdate,
      profileImageUrl: other.profileImageUrl,
      profilePhotoData: other.profilePhotoData,
      profilePhotoMimeType: other.profilePhotoMimeType ?? profilePhotoMimeType,
      emailVerified: emailVerified,
      isAccountDeactivated: isAccountDeactivated,
    );
  }

  static Map<String, dynamic> _asUserMap(Map<String, dynamic> json) {
    bool looksLikeUser(Map<String, dynamic> m) =>
        m.containsKey('email') ||
        m.containsKey('userName') ||
        m.containsKey('username') ||
        m.containsKey('id') ||
        m.containsKey('userId') ||
        m.containsKey('user_id');

    if (looksLikeUser(json)) return json;
    final u = json['user'];
    if (u is Map<String, dynamic> && looksLikeUser(u)) return u;
    final d = json['data'];
    if (d is Map<String, dynamic> && looksLikeUser(d)) return d;
    return json;
  }

  /// Backend `id` / `userId` / sayısal id farkları
  static String _coerceUserId(Map<String, dynamic> m) {
    for (final k in ['id', 'userId', 'user_id', 'uuid']) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static bool _accountDeactivatedFromMap(Map<String, dynamic> m) {
    final st = (m['status'] ?? m['accountStatus'] ?? '')
        .toString()
        .toLowerCase();
    if (st == 'deactivated' || st == 'inactive' || st == 'suspended') {
      return true;
    }
    if (m['active'] is bool && (m['active'] as bool) == false) {
      return true;
    }
    if (m['isActive'] is bool && (m['isActive'] as bool) == false) {
      return true;
    }
    if (m['enabled'] is bool && (m['enabled'] as bool) == false) {
      return true;
    }
    return false;
  }

  static String? _firstString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  /// `profilePhoto` bazen URL, bazen base64 olabiliyor.
  static ({String? url, String? data}) _splitProfilePhoto(String? raw) {
    if (raw == null) return (url: null, data: null);
    final t = raw.trim();
    if (t.isEmpty) return (url: null, data: null);
    final lower = t.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        t.startsWith('/') ||
        lower.startsWith('data:image/')) {
      return (url: t, data: null);
    }
    return (url: null, data: t);
  }

  factory UserResponseDto.fromJson(Map<String, dynamic> json) {
    final m = _asUserMap(json);

    String? imageUrl = _firstString(m, [
      'profileImageUrl',
      'profilePhotoUrl',
      'avatarUrl',
      'photoUrl',
      'imageUrl',
      'profilePicture',
      'picture',
    ]);

    String? photoData = _firstString(m, [
      'profilePhotoData',
      'avatarBase64',
      'photoData',
    ]);

    final mime = _firstString(m, ['profilePhotoMimeType', 'profileImageMimeType']);

    final genericPhoto = m['profilePhoto']?.toString().trim();
    if (genericPhoto != null && genericPhoto.isNotEmpty) {
      final split = _splitProfilePhoto(genericPhoto);
      imageUrl ??= split.url;
      photoData ??= split.data;
    }

    return UserResponseDto(
      id: _coerceUserId(m),
      email: m['email']?.toString() ?? '',
      userName: _firstString(m, ['userName', 'username', 'user_name']) ?? '',
      name: m['name']?.toString(),
      surname: m['surname']?.toString(),
      birthdate: m['birthdate']?.toString(),
      profileImageUrl: imageUrl,
      profilePhotoData: photoData,
      profilePhotoMimeType: mime,
      emailVerified: m['emailVerified'] as bool?,
      isAccountDeactivated: _accountDeactivatedFromMap(m),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'userName': userName,
      'name': name,
      'surname': surname,
      'birthdate': birthdate,
      'profileImageUrl': profileImageUrl,
      'profilePhotoData': profilePhotoData,
      'profilePhotoMimeType': profilePhotoMimeType,
      'emailVerified': emailVerified,
      'isAccountDeactivated': isAccountDeactivated,
    };
  }
}

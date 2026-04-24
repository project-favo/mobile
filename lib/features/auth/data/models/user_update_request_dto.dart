class UserUpdateRequestDto {
  final String? userName;
  final String? name;
  final String? surname;
  final String? birthdate;
  final String? profilePhotoBase64; // Base64 encoded profil fotoğrafı (data URI formatında)
  final String? profilePhotoMimeType; // MIME type (örn: "image/jpeg")
  /// `true` ise profil fotosu sunucudan kaldırılır (yeni yük yok).
  final bool clearProfilePhoto;
  final bool? profileAnonymous;

  UserUpdateRequestDto({
    this.userName,
    this.name,
    this.surname,
    this.birthdate,
    this.profilePhotoBase64,
    this.profilePhotoMimeType,
    this.clearProfilePhoto = false,
    this.profileAnonymous,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (userName != null) json['userName'] = userName;
    if (name != null) json['name'] = name;
    if (surname != null) json['surname'] = surname;
    if (birthdate != null) json['birthdate'] = birthdate;
    if (profileAnonymous != null) {
      json['profileAnonymous'] = profileAnonymous;
    }
    if (clearProfilePhoto) {
      json['removeProfilePhoto'] = true;
      json['clearProfilePhoto'] = true;
    } else if (profilePhotoBase64 != null) {
      json['profilePhotoBase64'] = profilePhotoBase64;
      if (profilePhotoMimeType != null) {
        json['profilePhotoMimeType'] = profilePhotoMimeType;
      }
    }

    return json;
  }
}


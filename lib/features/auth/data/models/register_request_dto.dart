class RegisterRequestDto {
  final String userName;
  final String name;
  final String surname;
  final String birthdate;
  final String? profilePhotoBase64; // Base64 encoded profil fotoğrafı (data URI formatında)
  final String? profilePhotoMimeType; // MIME type (örn: "image/jpeg")

  RegisterRequestDto({
    required this.userName,
    required this.name,
    required this.surname,
    required this.birthdate,
    this.profilePhotoBase64,
    this.profilePhotoMimeType,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'userName': userName,
      'name': name,
      'surname': surname,
      'birthdate': birthdate,
    };
    
    if (profilePhotoBase64 != null) {
      json['profilePhotoBase64'] = profilePhotoBase64!;
    }
    if (profilePhotoMimeType != null) {
      json['profilePhotoMimeType'] = profilePhotoMimeType!;
    }
    
    return json;
  }
}


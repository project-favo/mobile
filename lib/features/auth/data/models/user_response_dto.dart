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
  });

  /// Backend: null → legacy (verified), false → not verified, true → verified
  bool get isEmailVerified => emailVerified != false;

  factory UserResponseDto.fromJson(Map<String, dynamic> json) {
    return UserResponseDto(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      name: json['name']?.toString(),
      surname: json['surname']?.toString(),
      birthdate: json['birthdate']?.toString(),
      profileImageUrl: json['profileImageUrl']?.toString(),
      profilePhotoData: json['profilePhotoData']?.toString(),
      profilePhotoMimeType: json['profilePhotoMimeType']?.toString(),
      emailVerified: json['emailVerified'] as bool?,
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
    };
  }
}


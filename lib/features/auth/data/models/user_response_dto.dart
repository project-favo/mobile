class UserResponseDto {
  final String id;
  final String email;
  final String userName;
  final String? name;
  final String? surname;
  final String? birthdate;
  final String? profileImageUrl;

  UserResponseDto({
    required this.id,
    required this.email,
    required this.userName,
    this.name,
    this.surname,
    this.birthdate,
    this.profileImageUrl,
  });

  factory UserResponseDto.fromJson(Map<String, dynamic> json) {
    return UserResponseDto(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      name: json['name']?.toString(),
      surname: json['surname']?.toString(),
      birthdate: json['birthdate']?.toString(),
      profileImageUrl: json['profileImageUrl']?.toString(),
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
    };
  }
}


class UserResponseDto {
  final String id;
  final String email;
  final String userName;
  final String? profileImageUrl;

  UserResponseDto({
    required this.id,
    required this.email,
    required this.userName,
    this.profileImageUrl,
  });

  factory UserResponseDto.fromJson(Map<String, dynamic> json) {
    return UserResponseDto(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      profileImageUrl: json['profileImageUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'userName': userName,
      'profileImageUrl': profileImageUrl,
    };
  }
}


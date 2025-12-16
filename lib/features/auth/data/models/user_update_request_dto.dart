class UserUpdateRequestDto {
  final String userName;

  UserUpdateRequestDto({required this.userName});

  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
    };
  }
}


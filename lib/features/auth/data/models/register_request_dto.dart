class RegisterRequestDto {
  final String userName;
  final String name;
  final String surname;
  final String birthdate;

  RegisterRequestDto({
    required this.userName,
    required this.name,
    required this.surname,
    required this.birthdate,
  });

  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
      'name': name,
      'surname': surname,
      'birthdate': birthdate,
    };
  }
}


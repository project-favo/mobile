class UnreadCountDto {
  final int count;

  UnreadCountDto({required this.count});

  factory UnreadCountDto.fromJson(Map<String, dynamic> json) {
    return UnreadCountDto(
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}


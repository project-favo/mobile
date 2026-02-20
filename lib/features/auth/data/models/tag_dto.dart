class TagDto {
  final String id;
  final String name;
  final String? categoryPath;
  final String? parentId;

  TagDto({
    required this.id,
    required this.name,
    this.categoryPath,
    this.parentId,
  });

  factory TagDto.fromJson(Map<String, dynamic> json) {
    return TagDto(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      categoryPath: json['categoryPath']?.toString(),
      parentId: json['parentId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'categoryPath': categoryPath,
      'parentId': parentId,
    };
  }
}


import 'tag_dto.dart';

class ProductDto {
  final String id;
  final String name;
  final String imageURL;
  final String? description;
  final TagDto tag;

  ProductDto({
    required this.id,
    required this.name,
    required this.imageURL,
    this.description,
    required this.tag,
  });

  factory ProductDto.fromJson(Map<String, dynamic> json) {
    return ProductDto(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      imageURL: json['imageURL']?.toString() ?? '',
      description: json['description']?.toString(),
      tag: TagDto.fromJson(json['tag'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageURL': imageURL,
      'description': description,
      'tag': tag.toJson(),
    };
  }
}


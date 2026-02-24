import 'tag_dto.dart';

class ProductDto {
  final String id;
  final String name;
  final String imageURL;
  final String? description;
  final TagDto tag;
  final double? averageRating;
  final bool? isLiked;
  final DateTime? createdAt;

  ProductDto({
    required this.id,
    required this.name,
    required this.imageURL,
    this.description,
    required this.tag,
    this.averageRating,
    this.isLiked,
    this.createdAt,
  });

  factory ProductDto.fromJson(Map<String, dynamic> json) {
    return ProductDto(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      imageURL: json['imageURL']?.toString() ?? '',
      description: json['description']?.toString(),
      tag: TagDto.fromJson(json['tag'] ?? {}),
      averageRating: json['averageRating'] != null 
          ? (json['averageRating'] is num 
              ? json['averageRating'].toDouble() 
              : double.tryParse(json['averageRating'].toString()))
          : null,
      isLiked: json['isLiked'] as bool?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageURL': imageURL,
      'description': description,
      'tag': tag.toJson(),
      'averageRating': averageRating,
      'isLiked': isLiked,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  /// Yeni bir ProductDto oluşturur, sadece belirtilen alanları değiştirir
  ProductDto copyWith({
    String? id,
    String? name,
    String? imageURL,
    String? description,
    TagDto? tag,
    double? averageRating,
    bool? isLiked,
    DateTime? createdAt,
  }) {
    return ProductDto(
      id: id ?? this.id,
      name: name ?? this.name,
      imageURL: imageURL ?? this.imageURL,
      description: description ?? this.description,
      tag: tag ?? this.tag,
      // averageRating için: eğer null değilse (0.0 dahil) kullan, null ise this.averageRating kullan
      averageRating: averageRating != null ? averageRating : this.averageRating,
      // isLiked için: eğer null değilse (false dahil) kullan, null ise this.isLiked kullan
      isLiked: isLiked != null ? isLiked : this.isLiked,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}


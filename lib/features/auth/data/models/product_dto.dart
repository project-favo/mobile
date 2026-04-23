import '../../../../core/utils/product_listing_flags.dart';
import '../../../../core/utils/app_datetime.dart';
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

  /// GET /api/products JSON'unda askı / vitrinden kalkmış bilgisi.
  final bool isProductNotListed;

  /// [isActive: false] vb. tüm [isProductDataNotListedInMap] sinyalleri [isProductNotListed] içine işlenir.
  /// Ayrıca boş [imageURL] vitrin dışı kabul edilir.
  bool get isUnavailableForStorefront =>
      isProductNotListed || isNotListedImpliedByEmptyProductImage(imageURL);

  ProductDto({
    required this.id,
    required this.name,
    required this.imageURL,
    this.description,
    required this.tag,
    this.averageRating,
    this.isLiked,
    this.createdAt,
    this.isProductNotListed = false,
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
      createdAt: (json['createdAt'] ?? json['created_at']) != null
          ? parseBackendDateTimeToLocal(
              (json['createdAt'] ?? json['created_at']).toString(),
            )
          : null,
      isProductNotListed: isProductDataNotListedInMap(json),
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
      'isProductNotListed': isProductNotListed,
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
    bool? isProductNotListed,
  }) {
    return ProductDto(
      id: id ?? this.id,
      name: name ?? this.name,
      imageURL: imageURL ?? this.imageURL,
      description: description ?? this.description,
      tag: tag ?? this.tag,
      // averageRating için: eğer null değilse (0.0 dahil) kullan, null ise this.averageRating kullan
      averageRating: averageRating ?? this.averageRating,
      // isLiked için: eğer null değilse (false dahil) kullan, null ise this.isLiked kullan
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt ?? this.createdAt,
      isProductNotListed: isProductNotListed ?? this.isProductNotListed,
    );
  }
}


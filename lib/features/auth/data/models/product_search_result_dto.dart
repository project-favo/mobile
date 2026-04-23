import 'product_dto.dart';

class ProductSearchResultDto {
  final List<ProductDto> content;
  final int totalElements;
  final int totalPages;
  final int size;
  final int number;

  ProductSearchResultDto({
    required this.content,
    required this.totalElements,
    required this.totalPages,
    required this.size,
    required this.number,
  });

  factory ProductSearchResultDto.fromJson(Map<String, dynamic> json) {
    final items = (json['content'] as List? ?? [])
        .map((e) => ProductDto.fromJson(e as Map<String, dynamic>))
        .toList();

    return ProductSearchResultDto(
      content: items,
      totalElements:
          (json['totalElements'] as num?)?.toInt() ?? items.length,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      size: (json['size'] as num?)?.toInt() ?? items.length,
      number: (json['number'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content.map((e) => e.toJson()).toList(),
      'totalElements': totalElements,
      'totalPages': totalPages,
      'size': size,
      'number': number,
    };
  }
}


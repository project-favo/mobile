import 'review_dto.dart';

/// GET /api/reviews/me — Spring [Page] cevabı.
class MyReviewsPageResultDto {
  final List<ReviewDto> content;
  final int totalElements;
  final int totalPages;
  final int size;
  final int number;

  const MyReviewsPageResultDto({
    required this.content,
    required this.totalElements,
    required this.totalPages,
    required this.size,
    required this.number,
  });

  bool get hasNextPage => totalPages > 0 && number + 1 < totalPages;

  factory MyReviewsPageResultDto.fromJson(Map<String, dynamic> json) {
    final items = (json['content'] as List? ?? [])
        .map((e) => ReviewDto.fromJson(e as Map<String, dynamic>))
        .toList();
    return MyReviewsPageResultDto(
      content: items,
      totalElements: (json['totalElements'] as num?)?.toInt() ?? items.length,
      totalPages: (json['totalPages'] as num?)?.toInt() ??
          (items.isEmpty ? 0 : 1),
      size: (json['size'] as num?)?.toInt() ?? items.length,
      number: (json['number'] as num?)?.toInt() ?? 0,
    );
  }
}

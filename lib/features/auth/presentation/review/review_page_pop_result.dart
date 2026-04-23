import '../../data/models/product_dto.dart';

/// [ReviewPage]’den dönünce grid’in eski beğeni sayısı flash’lemeden güncellenmesi için.
class ReviewPagePopResult {
  const ReviewPagePopResult({
    required this.product,
    required this.likeCount,
    required this.reviewCount,
  });

  final ProductDto product;
  final int likeCount;
  final int reviewCount;
}

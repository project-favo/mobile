import 'package:favo_mobile/core/utils/entity_active.dart';
import 'package:favo_mobile/core/utils/review_visibility_flags.dart';
import 'package:favo_mobile/features/activity/data/friends_feed_dto.dart';
import 'package:favo_mobile/features/auth/data/models/product_dto.dart';
import 'package:favo_mobile/features/auth/data/models/review_dto.dart';
import 'package:favo_mobile/features/auth/data/models/tag_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isProductEntityActive', () {
    test('true when product is listed', () {
      final p = ProductDto(
        id: '1',
        name: 'X',
        imageURL: 'https://x/y.png',
        tag: TagDto(id: 't', name: 't'),
        isProductNotListed: false,
      );
      expect(isProductEntityActive(p), isTrue);
    });

    test('false when product not listed', () {
      final p = ProductDto(
        id: '1',
        name: 'X',
        imageURL: 'https://x/y.png',
        tag: TagDto(id: 't', name: 't'),
        isProductNotListed: true,
      );
      expect(isProductEntityActive(p), isFalse);
    });
  });

  group('isReviewEntityVisible', () {
    ReviewDto base({bool productNotListed = false, bool reviewInactive = false}) {
      return ReviewDto(
        id: 'r1',
        title: 't',
        isCollaborative: false,
        rating: 5,
        createdAt: '2020-01-01',
        productId: 'p1',
        productName: 'P',
        ownerId: 'o1',
        ownerUserName: 'u',
        mediaList: const [],
        likeCount: 0,
        isLikedByCurrentUser: false,
        isProductNotListed: productNotListed,
        isReviewInactive: reviewInactive,
      );
    }

    test('false when review inactive', () {
      expect(isReviewEntityVisible(base(reviewInactive: true)), isFalse);
    });

    test('false when product not listed on review', () {
      expect(isReviewEntityVisible(base(productNotListed: true)), isFalse);
    });

    test('true when both active', () {
      expect(isReviewEntityVisible(base()), isTrue);
    });
  });

  group('isFriendsFeedItemForUi', () {
    test('hides when actor inactive', () {
      final fromJson = FriendsFeedItemDto.fromJson({
        'id': '1',
        'type': 'REVIEW',
        'actorUserId': '2',
        'actorUserName': 'U',
        'productId': 'p1',
        'isActive': false,
      });
      expect(isFriendsFeedItemForUi(fromJson), isFalse);
    });

    test('hides when product not listed in nested product', () {
      final fromJson = FriendsFeedItemDto.fromJson({
        'id': '1',
        'type': 'REVIEW',
        'actorUserId': '2',
        'actorUserName': 'U',
        'productId': 'p1',
        'productName': 'P',
        'product': {'isActive': false},
      });
      expect(isFriendsFeedItemForUi(fromJson), isFalse);
    });
  });

  group('isReviewDataInactiveOrHiddenInMap', () {
    test('detects isActive false', () {
      expect(
        isReviewDataInactiveOrHiddenInMap({'isActive': false}),
        isTrue,
      );
    });

    test('allows default', () {
      expect(
        isReviewDataInactiveOrHiddenInMap({'id': '1', 'rating': 5}),
        isFalse,
      );
    });
  });
}

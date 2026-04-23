import 'dart:async';

import '../../../../core/cache/review_memory_cache.dart';
import '../../../../core/utils/entity_active.dart';
import '../../../../core/utils/session_helper.dart';
import '../models/product_dto.dart';
import '../repositories/review_repository.dart';

/// Lightweight background prefetcher for review lists.
///
/// Goal: reduce loading flicker when opening ReviewPage by warming
/// review cache for likely-to-open products.
class ReviewPrefetchService {
  ReviewPrefetchService._();
  static final ReviewPrefetchService instance = ReviewPrefetchService._();

  final ReviewRepository _reviewRepository = ReviewRepository();
  final SessionHelper _sessionHelper = SessionHelper();

  final Set<String> _inFlight = <String>{};
  final Map<String, DateTime> _lastPrefetchedAt = <String, DateTime>{};

  static const Duration _ttl = Duration(seconds: 45);

  void prefetchForProducts(List<ProductDto> products, {int maxCount = 4}) {
    if (products.isEmpty || maxCount <= 0) return;

    final now = DateTime.now();
    final productIds =
        products
            .map((p) => p.id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

    final eligibleIds = <String>[];
    for (final id in productIds) {
      if (eligibleIds.length >= maxCount) break;
      if (_inFlight.contains(id)) continue;
      final last = _lastPrefetchedAt[id];
      if (last != null && now.difference(last) < _ttl) continue;
      eligibleIds.add(id);
    }

    if (eligibleIds.isEmpty) return;
    unawaited(_runBatch(eligibleIds));
  }

  Future<void> _runBatch(List<String> productIds) async {
    final token = await _sessionHelper.ensureSession();
    for (final id in productIds) {
      _inFlight.add(id);
      unawaited(_prefetchOne(productId: id, firebaseIdToken: token));
    }
  }

  Future<void> _prefetchOne({
    required String productId,
    required String? firebaseIdToken,
  }) async {
    try {
      final reviews = await _reviewRepository.getReviewsByProductId(
        productId,
        firebaseIdToken: firebaseIdToken,
      );
      ReviewMemoryCache.instance.remember(
        productId,
        filterVisibleReviews(reviews),
      );
      _lastPrefetchedAt[productId] = DateTime.now();
    } catch (_) {
      // Prefetch is best effort; intentionally swallow errors.
    } finally {
      _inFlight.remove(productId);
    }
  }
}


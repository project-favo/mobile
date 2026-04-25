import '../../features/auth/data/models/feed_sort_option.dart';
import '../../features/auth/data/models/product_dto.dart';

class HomeViewState {
  const HomeViewState({
    required this.products,
    required this.currentPage,
    required this.totalPages,
    required this.totalElements,
    required this.selectedCategoryIndex,
    required this.selectedSubCategoryIndex,
    required this.activeCategoryPathPrefix,
    required this.activeSortOption,
    required this.scrollOffset,
    required this.isBannerCollapsed,
  });

  final List<ProductDto> products;
  final int currentPage;
  final int totalPages;
  final int totalElements;
  final int selectedCategoryIndex;
  final int selectedSubCategoryIndex;
  final String? activeCategoryPathPrefix;
  final FeedSortOption activeSortOption;
  final double scrollOffset;
  final bool isBannerCollapsed;
}

/// In-memory HomePage UI snapshot to keep state on tab switches.
class HomeViewStateCache {
  HomeViewStateCache._();
  static final HomeViewStateCache instance = HomeViewStateCache._();

  HomeViewState? _memory;

  HomeViewState? peek() {
    final s = _memory;
    if (s == null || s.products.isEmpty) return null;
    return HomeViewState(
      products: List<ProductDto>.from(s.products),
      currentPage: s.currentPage,
      totalPages: s.totalPages,
      totalElements: s.totalElements,
      selectedCategoryIndex: s.selectedCategoryIndex,
      selectedSubCategoryIndex: s.selectedSubCategoryIndex,
      activeCategoryPathPrefix: s.activeCategoryPathPrefix,
      activeSortOption: s.activeSortOption,
      scrollOffset: s.scrollOffset,
      isBannerCollapsed: s.isBannerCollapsed,
    );
  }

  void set(HomeViewState state) {
    _memory = HomeViewState(
      products: List<ProductDto>.from(state.products),
      currentPage: state.currentPage,
      totalPages: state.totalPages,
      totalElements: state.totalElements,
      selectedCategoryIndex: state.selectedCategoryIndex,
      selectedSubCategoryIndex: state.selectedSubCategoryIndex,
      activeCategoryPathPrefix: state.activeCategoryPathPrefix,
      activeSortOption: state.activeSortOption,
      scrollOffset: state.scrollOffset,
      isBannerCollapsed: state.isBannerCollapsed,
    );
  }

  void clear() {
    _memory = null;
  }
}


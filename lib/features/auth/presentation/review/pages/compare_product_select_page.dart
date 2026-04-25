import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_decorations.dart';
import '../../../../../core/utils/session_helper.dart';
import '../../../../../core/utils/product_rating_display.dart';
import '../../../../../core/widgets/skeleton_loader.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/repositories/product_repository.dart';
import 'product_comparison_page.dart';

/// Compare: 2. ürünü seç. Aynı üst kategorideki tüm ürünler listelenir.
class CompareProductSelectPage extends StatefulWidget {
  final ProductDto product1;

  const CompareProductSelectPage({super.key, required this.product1});

  @override
  State<CompareProductSelectPage> createState() => _CompareProductSelectPageState();
}

class _CompareProductSelectPageState extends State<CompareProductSelectPage> {
  final ProductRepository _productRepository = ProductRepository();
  final SessionHelper _sessionHelper = SessionHelper();
  final TextEditingController _searchController = TextEditingController();
  List<ProductDto> _products = [];
  bool _isLoadingProducts = true;
  bool _isSelectingProduct = false;
  String? _errorMessage;
  String _searchQuery = '';

  List<ProductDto> get _filteredProducts {
    if (_searchQuery.trim().isEmpty) return _products;
    final q = _searchQuery.trim().toLowerCase();
    return _products.where((p) {
      return p.name.toLowerCase().contains(q) || p.tag.name.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() {
      _isLoadingProducts = true;
      _errorMessage = null;
    });
    try {
      final path = widget.product1.tag.categoryPath ?? widget.product1.tag.name;
      final prefix = path.contains('.') ? path.substring(0, path.lastIndexOf('.')) : path;
      if (prefix.isEmpty) {
        if (!mounted) return;
        setState(() {
          _products = [];
          _isLoadingProducts = false;
        });
        return;
      }
      const pageSize = 50;
      int page = 0;
      final List<ProductDto> all = [];
      int totalPages = 1;
      do {
        final result = await _productRepository.searchProductsRaw(
          categoryPathPrefix: prefix,
          page: page,
          size: pageSize,
        );
        totalPages = result.totalPages;
        for (final p in result.content) {
          if (p.id != widget.product1.id) all.add(p);
        }
        page++;
        if (!mounted) return;
      } while (page < totalPages);
      if (!mounted) return;
      setState(() {
        _products = all;
        _isLoadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoadingProducts = false;
      });
    }
  }

  Future<void> _onProductSelected(ProductDto product2) async {
    if (_isSelectingProduct) return;
    setState(() => _isSelectingProduct = true);
    try {
      final token = await _sessionHelper.getTokenAndSetHeader();
      final product2WithRating = await _productRepository.getProductById(
        product2.id,
        firebaseIdToken: token,
        bypassCache: true,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductComparisonPage(
            product1: widget.product1,
            product2: product2WithRating,
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _isSelectingProduct = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSelectingProduct = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load product: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Text(
          'Choose to compare',
          style: AppTextStyles.heading3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "Comparing from" source card
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xLarge,
                  0,
                  AppSpacing.xLarge,
                  AppSpacing.xLarge,
                ),
                child: _SourceProductBanner(product: widget.product1),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    hintStyle: AppTextStyles.bodySecondary,
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.border.withOpacity(0.5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  ),
                  style: AppTextStyles.body,
                ),
              ),
              const SizedBox(height: AppSpacing.xLarge),
              // List
              Expanded(
                child: _isLoadingProducts
                    ? ListView(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
                        children: [
                          for (var i = 0; i < 7; i++) const CompareProductRowSkeleton(),
                        ],
                      )
                    : _errorMessage != null
                        ? _buildErrorState()
                        : _filteredProducts.isEmpty
                            ? _buildEmptyState()
                            : _buildProductList(),
              ),
            ],
          ),
          if (_isSelectingProduct)
            const ColoredBox(
              color: Colors.black26,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.textSecondary.withOpacity(0.5)),
            const SizedBox(height: AppSpacing.xLarge),
            Text(
              'Failed to load products',
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.medium),
            Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.xxLarge),
            TextButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: AppColors.textSecondary.withOpacity(0.5)),
            const SizedBox(height: AppSpacing.xLarge),
            Text(
              _searchQuery.trim().isEmpty
                  ? 'No other products in this category'
                  : 'No results for "$_searchQuery"',
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xLarge,
        0,
        AppSpacing.xLarge,
        AppSpacing.xxLarge,
      ),
      itemCount: _filteredProducts.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.medium),
      itemBuilder: (context, index) {
        final p = _filteredProducts[index];
        return _ProductRow(
          product: p,
          onTap: () => _onProductSelected(p),
        );
      },
    );
  }
}

// ── Source product banner ────────────────────────────────────────────────────

class _SourceProductBanner extends StatelessWidget {
  final ProductDto product;
  const _SourceProductBanner({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              product.imageURL,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 44,
                height: 44,
                color: AppColors.background,
                child: const Icon(Icons.image_not_supported_rounded,
                    color: AppColors.textSecondary, size: 20),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COMPARING FROM',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.compare_arrows_rounded, color: AppColors.primary, size: 20),
        ],
      ),
    );
  }
}

// ── Product row item ─────────────────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  final ProductDto product;
  final VoidCallback onTap;
  const _ProductRow({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppDecorations.softCardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    product.imageURL,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: AppColors.background,
                      child: const Icon(Icons.image_not_supported_rounded,
                          color: AppColors.textSecondary, size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.large),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        product.tag.name.toUpperCase(),
                        style: AppTextStyles.productCategory.copyWith(fontSize: 9),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (productHasMeaningfulRating(product.averageRating)) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 13, color: AppColors.primary),
                            const SizedBox(width: 3),
                            Text(
                              product.averageRating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.medium),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

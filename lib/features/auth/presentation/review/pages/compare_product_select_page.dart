import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../data/models/product_dto.dart';
import '../../../data/repositories/product_repository.dart';
import 'product_comparison_page.dart';

/// Compare: select 2nd product. Only products in the same category are shown
/// (e.g. smartphone → only other smartphones). One fast API call, no rating/like.
class CompareProductSelectPage extends StatefulWidget {
  final ProductDto product1;

  const CompareProductSelectPage({super.key, required this.product1});

  @override
  State<CompareProductSelectPage> createState() =>
      _CompareProductSelectPageState();
}

class _CompareProductSelectPageState extends State<CompareProductSelectPage> {
  final ProductRepository _productRepository = ProductRepository();
  final TextEditingController _searchController = TextEditingController();
  List<ProductDto> _products = [];
  bool _isLoadingProducts = true;
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

  /// Aynı kategorideki tüm ürünler: search API ile categoryPathPrefix kullanılıyor (sadece kategori, isim yok).
  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() {
      _isLoadingProducts = true;
      _errorMessage = null;
    });
    try {
      final prefix = widget.product1.tag.categoryPath ?? widget.product1.tag.name;
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

  void _onProductSelected(ProductDto product2) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductComparisonPage(
          product1: widget.product1,
          product2: product2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Text(
          'Select 2nd Product',
          style: AppTextStyles.heading3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 22),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: AppTextStyles.body,
            ),
          ),
          Expanded(
            child: _isLoadingProducts
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xLarge),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Failed to load products. Please try again.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: AppSpacing.xLarge),
                              TextButton(
                                onPressed: _loadProducts,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredProducts.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.trim().isEmpty
                                  ? 'No other products to compare.'
                                  : 'No products match "$_searchQuery".',
                              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
                            itemCount: _filteredProducts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.medium),
                            itemBuilder: (context, index) {
                              final p = _filteredProducts[index];
                              return Material(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  onTap: () => _onProductSelected(p),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(AppSpacing.large),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            p.imageURL,
                                            width: 64,
                                            height: 64,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: 64,
                                              height: 64,
                                              color: AppColors.textSecondary.withOpacity(0.1),
                                              child: const Icon(Icons.image_not_supported, color: AppColors.textSecondary),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.xLarge),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p.name,
                                                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                p.tag.name,
                                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                              ),
                                              if (p.averageRating != null) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.star, size: 14, color: AppColors.primary),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      (p.averageRating!).toStringAsFixed(1),
                                                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

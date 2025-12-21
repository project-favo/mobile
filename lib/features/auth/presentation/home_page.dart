import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_chip_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../widgets/product_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Örnek ürün listesi
    final List<Map<String, dynamic>> products = [
      {
        "imageUrl":
        "https://ce1999-mudo.akinoncloudcdn.com/products/2024/10/30/547665/4957dc47-e013-4617-a889-6355ada4da42.jpg",
        "title": "MUDO DARSEY Blanket",
        "category": "HOME",
        "rating": 4,
        "desc":
        "Produced in accordance with Oeko-Tex 100 quality standards. Our products with an internationally valid...",
        "isFavorite": true,
      },
      {
        "imageUrl":
        "https://cdn.dsmcdn.com/mnresize/-/280/ty1547/product/media/images/ty1545/prod/QC/20240915/14/6fbbdd8f-9758-353f-b95b-0819ac60133b/1_org_zoom.jpg",
        "title": "SONY WH-CH520 Headphone",
        "category": "TECHNOLOGY",
        "rating": 5,
        "desc": "Wireless headphone with long battery life and deep bass.",
        "isFavorite": false,
      },
      {
        "imageUrl":
        "https://happyskincosmetics.com/cdn/shop/files/all_around_powder_brush_7_V2_2048x.jpg?v=1720252548",
        "title": "Makeup Brush Set",
        "category": "BEAUTY",
        "rating": 3,
        "desc": "Professional makeup brushes for flawless application.",
        "isFavorite": false,
      },
      {
        "imageUrl":
        "https://olivias.com/cdn/shop/collections/Untitled_design_22_9b78b3b7-732b-47c7-80b8-a9000b37204e.jpg?v=1761061282",
        "title": "Luxury Sofa Cushion",
        "category": "HOME",
        "rating": 4,
        "desc": "Soft and stylish cushion for your sofa or armchair.",
        "isFavorite": true,
      },
      {
        "imageUrl":
        "https://ideacdn.net/idea/fp/51/myassets/products/555/gb-m12w-main.jpg?revision=1733401561",
        "title": "Gaming Mouse",
        "category": "TECHNOLOGY",
        "rating": 5,
        "desc": "High precision gaming mouse with customizable buttons.",
        "isFavorite": true,
      },
      {
        "imageUrl":
        "https://innovist.com/cdn/shop/files/Vit-C-first-imageFirst-Image-Guides.jpg?v=1756544774",
        "title": "Face Serum",
        "category": "BEAUTY",
        "rating": 4,
        "desc": "Hydrating serum with vitamin C for glowing skin.",
        "isFavorite": true,
      },
      {
        "imageUrl":
        "https://www.nativeunion.com/cdn/shop/files/DeskStand_Sandstone_1200x1200_crop_center.png?v=1755767340",
        "title": "Laptop Stand",
        "category": "TECHNOLOGY",
        "rating": 4,
        "desc": "Ergonomic laptop stand suitable for all sizes.",
        "isFavorite": true,
      },
      {
        "imageUrl":
        "https://m.media-amazon.com/images/I/61s1AsMBKAL.jpg",
        "title": "Organic Pillow",
        "category": "HOME",
        "rating": 3,
        "desc": "Comfortable organic pillow for better sleep.",
        "isFavorite": false,
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'FAVO',
          style: AppTextStyles.HomeHeader,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble),
            color: AppColors.primary,
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(
          left: AppSpacing.xLarge,
          right: AppSpacing.xLarge,
          bottom: AppSpacing.xLarge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// CATEGORIES
            SizedBox(
              height: AppSpacing.categoryChipHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: const [
                  _CategoryChip(title: 'BEAUTY'),
                  _CategoryChip(title: 'HOME', selected: true),
                  _CategoryChip(title: 'TECHNOLOGY'),
                  _CategoryChip(title: 'MAKEUP'),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxLarge),

            /// PRODUCT GRID
            Wrap(
              spacing: AppSpacing.xLarge,
              runSpacing: AppSpacing.xLarge,
              children: products.map((product) {
                return SizedBox(
                  width:
                  (MediaQuery.of(context).size.width - AppSpacing.xLarge * 2 - AppSpacing.xLarge) /
                      2, // 2 sütun
                  child: ProductCard(
                    imageUrl: product["imageUrl"],
                    title: product["title"],
                    category: product["category"],
                    rating: product["rating"].toDouble(),
                    desc: product["desc"],
                    isFavorite: product["isFavorite"],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_border), label: 'Favorites'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

/// CATEGORY CHIP
class _CategoryChip extends StatelessWidget {
  final String title;
  final bool selected;

  const _CategoryChip({
    required this.title,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.large),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
        alignment: Alignment.center,
        decoration: AppChipStyles.categoryChipDecoration(selected: selected),
        child: Text(
          title,
          style: AppChipStyles.categoryChipText(selected: selected),
        ),
      ),
    );
  }
}

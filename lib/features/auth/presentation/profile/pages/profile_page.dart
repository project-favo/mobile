import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../auth/data/services/auth_service.dart';
import '../../../../auth/data/models/user_response_dto.dart';
import '../../home_page.dart';
import '../../search_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AuthService _authService = AuthService();
  UserResponseDto? _user;
  bool _isLoading = true;
  String? _errorMessage;

  Route _noAnimationRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  BottomNavigationBar _buildBottomNavigationBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 4,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      onTap: (index) {
        if (index == 4) return;
        if (index == 0) {
          Navigator.pushReplacement(context, _noAnimationRoute(const HomePage()));
          return;
        }
        if (index == 1) {
          Navigator.pushReplacement(context, _noAnimationRoute(const SearchPage()));
          return;
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
        BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
        BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border), label: 'Favorites'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _authService.getMe();
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
    return Scaffold(
        backgroundColor: AppColors.background,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Profile',
            style: AppTextStyles.HomeHeader,
          ),
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    if (_errorMessage != null || _user == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Profile',
            style: AppTextStyles.HomeHeader,
          ),
        centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage ?? 'Failed to load user data',
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.large),
              ElevatedButton(
                onPressed: _loadUserData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: AppTextStyles.HomeHeader,
          ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
                color: AppColors.primary,
            onPressed: () async {
              // Settings'ten geri dönüldüğünde profil verilerini yeniden yükle
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsPage(),
            ),
              );
              // Settings'ten geri dönüldüğünde (özellikle Edit Profile yapıldıysa) verileri yenile
              if (result == true || mounted) {
                _loadUserData();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxLarge),

          // Avatar - Profil fotoğrafı varsa göster
          CircleAvatar(
            radius: 50,
            backgroundColor: AppColors.surface,
            backgroundImage: _user!.profilePhotoData != null && _user!.profilePhotoData!.isNotEmpty
                ? MemoryImage(
                    base64Decode(_user!.profilePhotoData!),
                  )
                : null,
            child: _user!.profilePhotoData == null || _user!.profilePhotoData!.isEmpty
                ? const Icon(
                    Icons.person_outline_rounded,
                    size: 60,
                    color: AppColors.primary,
                  )
                : null,
          ),

          const SizedBox(height: AppSpacing.large),

            // Name and Surname - Backend'den gelen name ve surname
            // Eğer name ve surname varsa göster, yoksa sadece username göster
            if (_user!.name != null || _user!.surname != null) ...[
          Text(
                '${_user!.name ?? ''} ${_user!.surname ?? ''}'.trim(),
            style: AppTextStyles.titleMedium,
          ),
              const SizedBox(height: AppSpacing.small),
              // Username (name/surname varsa altında göster)
          Text(
                '@${_user!.userName.toLowerCase().replaceAll(' ', '')}',
            style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ] else ...[
              // Sadece username göster (name/surname yoksa)
              Text(
                '@${_user!.userName.toLowerCase().replaceAll(' ', '')}',
                style: AppTextStyles.titleMedium,
          ),
            ],

            const SizedBox(height: AppSpacing.xxLarge),

            // Statistics
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatItem(label: '2.4K Followers'),
                const SizedBox(width: AppSpacing.xxLarge),
                _StatItem(label: '342 Following'),
                const SizedBox(width: AppSpacing.xxLarge),
                _StatItem(label: '128 Reviews'),
              ],
            ),

            const SizedBox(height: AppSpacing.xxLarge),

            // Follow Button
            SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.medium),
          ),
                child: const Text(
                  'Follow',
                  style: AppTextStyles.button,
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xxLarge),

            // Summary Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'AVERAGE RATING',
                      content: '4.2 /5.0',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xLarge),
                  Expanded(
                    child: _SummaryCard(
                      title: 'TOP CATEGORY',
                      content: 'Electronics 35%\nBeauty 30%\nFashion 20%',
          ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxLarge),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              tabs: const [
                Tab(text: 'My Reviews'),
                Tab(text: 'Favorites'),
                Tab(text: 'Wishlist'),
              ],
          ),

            const SizedBox(height: AppSpacing.large),

            // Sort By Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xLarge),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SORT BY',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Row(
                    children: [
                      _SortDropdown(
                        label: 'Date',
                        items: ['Newest', 'Oldest'],
                      ),
                      const SizedBox(width: AppSpacing.large),
                      _SortDropdown(
                        label: 'Rating',
                        items: ['Highest', 'Lowest'],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxLarge),

            // Tab Content Placeholder
            SizedBox(
              height: 300,
              child: TabBarView(
                controller: _tabController,
                children: const [
                  Center(child: Text('My Reviews content')),
                  Center(child: Text('Favorites content')),
                  Center(child: Text('Wishlist content')),
                ],
          ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;

  const _StatItem({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label.split(' ')[0],
          style: AppTextStyles.heading3,
        ),
        const SizedBox(height: AppSpacing.small),
        Text(
          label.split(' ').skip(1).join(' '),
          style: AppTextStyles.bodySecondary,
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String content;

  const _SummaryCard({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xLarge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.bodySecondary.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.medium),
          Text(
            content,
            style: AppTextStyles.heading3,
          ),
        ],
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final String label;
  final List<String> items;

  const _SortDropdown({
    required this.label,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: items[0],
      underline: Container(),
      style: AppTextStyles.bodyMedium,
      items: items.map((String item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(item),
        );
      }).toList(),
      onChanged: (String? newValue) {
        // Handle sort change
      },
      icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
    );
  }
}

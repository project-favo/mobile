import 'package:flutter/material.dart';

import 'activity_bottom_nav_icon.dart';

/// Main tabs: Search, Add (+), Home (center), Activity (bolt), Profile.
class MainBottomNavItems {
  MainBottomNavItems._();

  static List<BottomNavigationBarItem> get barItems => [
        const BottomNavigationBarItem(
          icon: Icon(Icons.search),
          label: 'Search',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.add),
          label: 'Add',
        ),
        const BottomNavigationBarItem(
          icon: Icon(
            Icons.home,
            size: 32,
          ),
          label: 'Home',
        ),
        const BottomNavigationBarItem(
          icon: ActivityBottomNavIcon(),
          label: 'Activity',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ];
}

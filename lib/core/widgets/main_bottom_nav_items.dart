import 'package:flutter/material.dart';

import 'activity_bottom_nav_icon.dart';

/// Main tabs: Search, Following feed, Home, Activity, Profile.
class MainBottomNavItems {
  MainBottomNavItems._();

  static List<BottomNavigationBarItem> get barItems => [
        const BottomNavigationBarItem(
          icon: Icon(Icons.search),
          label: 'Search',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.people_alt_outlined),
          label: 'Following',
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

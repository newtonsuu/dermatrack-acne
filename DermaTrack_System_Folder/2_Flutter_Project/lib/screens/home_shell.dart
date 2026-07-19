import 'package:flutter/material.dart';

import '../widgets/nav_profile_icon.dart';
import 'calendar_screen.dart';
import 'camera_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';

/// Bottom-nav container hosting the primary tabs.
///
/// Tabs:
///   Home      — Dashboard (today's status + quick scan)
///   Scan      — Camera flow
///   Calendar  — Monthly grid of scan history
///   Profile   — Account + recent scans
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  static const List<Widget> _tabs = [
    DashboardScreen(),
    CameraScreen(),
    CalendarScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Scan',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          // Profile tab shows the user's photo (or initials) instead of a
          // generic person glyph.
          const NavigationDestination(
            icon: NavProfileIcon(selected: false),
            selectedIcon: NavProfileIcon(selected: true),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

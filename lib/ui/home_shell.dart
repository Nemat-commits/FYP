import 'package:flutter/material.dart';

import 'screens/diagnostics_screen.dart';
import 'screens/gpx_history_screen.dart';
import 'screens/live_map_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    LiveMapScreen(),
    GpxHistoryScreen(),
    DiagnosticsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map),
            label: 'Live Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.route),
            label: 'GPX History',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart),
            label: 'Diagnostics',
          ),
        ],
      ),
    );
  }
}

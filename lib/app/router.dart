import 'package:flutter/material.dart';

import '../features/inbox/inbox_page.dart';
import '../features/settings/settings_page.dart';

enum AppTab {
  inbox('Inbox', Icons.inbox_outlined, Icons.inbox),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const AppTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tab = AppTab.values[_selectedIndex];

    return Scaffold(
      appBar: AppBar(title: Text(tab.label)),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          InboxPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: [
          for (final t in AppTab.values)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}

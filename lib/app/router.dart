import 'package:flutter/material.dart';

import '../core/backend/app_backend.dart';
import '../core/session/session_scope.dart';
import '../features/chat/chat_page.dart';
import '../features/settings/settings_page.dart';
import '../src/rust/db.dart';

enum AppTab {
  mainStream('Main', Icons.chat_bubble_outline, Icons.chat_bubble),
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
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const <Widget>[
          _MainStreamTab(),
          _SettingsTab(),
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

final class _MainStreamTab extends StatefulWidget {
  const _MainStreamTab();

  @override
  State<_MainStreamTab> createState() => _MainStreamTabState();
}

final class _MainStreamTabState extends State<_MainStreamTab> {
  Future<Conversation>? _conversationFuture;

  Future<Conversation> _load() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    return backend.getOrCreateMainStreamConversation(sessionKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conversationFuture ??= _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Conversation>(
      future: _conversationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Load failed: ${snapshot.error}')));
        }

        final conversation = snapshot.data;
        if (conversation == null) {
          return const Scaffold(body: Center(child: Text('Missing Main Stream')));
        }
        return ChatPage(conversation: conversation);
      },
    );
  }
}

final class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SettingsPage(),
    );
  }
}

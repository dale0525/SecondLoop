import 'package:flutter/material.dart';

import '../core/backend/app_backend.dart';
import '../core/session/session_scope.dart';
import '../features/chat/chat_page.dart';
import '../features/settings/settings_page.dart';
import '../i18n/strings.g.dart';
import '../src/rust/db.dart';
import '../ui/sl_glass.dart';
import '../ui/sl_surface.dart';
import '../ui/sl_tokens.dart';

enum AppTab {
  mainStream(Icons.chat_bubble_outline, Icons.chat_bubble),
  settings(Icons.settings_outlined, Icons.settings);

  const AppTab(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String label(BuildContext context) => switch (this) {
        AppTab.mainStream => context.t.app.tabs.main,
        AppTab.settings => context.t.app.tabs.settings,
      };
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
    final tokens = SlTokens.of(context);
    final mediaQuery = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;
        final content = useRail
            ? IndexedStack(
                index: _selectedIndex,
                children: const <Widget>[
                  _MainStreamTab(),
                  _SettingsTab(),
                ],
              )
            : const _MainStreamTab();

        return Scaffold(
          body: useRail
              ? Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: 92,
                        child: SlGlass(
                          borderRadius: BorderRadius.circular(tokens.radiusLg),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: NavigationRail(
                            selectedIndex: _selectedIndex,
                            onDestinationSelected: (index) =>
                                setState(() => _selectedIndex = index),
                            labelType: NavigationRailLabelType.all,
                            destinations: [
                              for (final t in AppTab.values)
                                NavigationRailDestination(
                                  icon: Icon(t.icon),
                                  selectedIcon: Icon(t.selectedIcon),
                                  label: Text(t.label(context)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SlPageSurface(
                        margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(tokens.radiusLg),
                          child: content,
                        ),
                      ),
                    ),
                  ],
                )
              : SlPageSurface(
                  margin: EdgeInsets.fromLTRB(
                    12,
                    12 + mediaQuery.viewPadding.top,
                    12,
                    0,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(tokens.radiusLg),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: content,
                    ),
                  ),
                ),
          bottomNavigationBar: null,
        );
      },
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
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Text(
            context.t.errors.loadFailed(error: '${snapshot.error}'),
          )));
        }

        final conversation = snapshot.data;
        if (conversation == null) {
          return Scaffold(
            body: Center(child: Text(context.t.errors.missingMainStream)),
          );
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
      appBar: AppBar(title: Text(context.t.settings.title)),
      body: const SettingsPage(),
    );
  }
}

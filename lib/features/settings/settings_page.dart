import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/background_sync.dart';
import 'llm_profiles_page.dart';
import 'sync_settings_page.dart';
import 'semantic_search_debug_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _autoUnlockEnabled;
  bool _busy = false;

  Future<void> _load() async {
    final backend = AppBackendScope.of(context);
    final enabled = await backend.readAutoUnlockEnabled();
    if (!mounted) return;
    setState(() => _autoUnlockEnabled = enabled);
  }

  Future<void> _setAutoUnlock(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      await backend.persistAutoUnlockEnabled(enabled: enabled);
      if (enabled) {
        await backend.saveSessionKey(sessionKey);
      }
      await BackgroundSync.refreshSchedule(backend: backend);
      if (mounted) setState(() => _autoUnlockEnabled = enabled);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _autoUnlockEnabled ??= true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _autoUnlockEnabled;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Auto unlock'),
          subtitle: const Text('Store a session key in secure storage'),
          value: enabled ?? true,
          onChanged: (_busy || enabled == null) ? null : _setAutoUnlock,
        ),
        const SizedBox(height: 12),
        ListTile(
          title: const Text('Lock now'),
          subtitle: const Text('Return to the unlock screen'),
          onTap: _busy ? null : SessionScope.of(context).lock,
        ),
        const SizedBox(height: 12),
        ListTile(
          title: const Text('LLM profiles'),
          subtitle: const Text('Configure BYOK for Ask AI'),
          onTap: _busy
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LlmProfilesPage()),
                  );
                },
        ),
        const SizedBox(height: 12),
        ListTile(
          title: const Text('Sync'),
          subtitle: const Text('Vault backends + auto sync settings'),
          onTap: _busy
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SyncSettingsPage()),
                  );
                },
        ),
        if (kDebugMode) ...[
          const Divider(height: 24),
          ListTile(
            title: const Text('Debug: Semantic search'),
            subtitle: const Text('Search similar messages + rebuild embeddings index'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SemanticSearchDebugPage()),
              );
            },
          ),
        ],
      ],
    );
  }
}

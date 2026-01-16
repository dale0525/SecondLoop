import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/background_sync.dart';
import '../../core/sync/sync_config_store.dart';
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

  Future<void> _resetLocalData() async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset local data?'),
          content: const Text(
            'This will delete local database + auth file and clear sync/auto-unlock secure storage. '
            'You will need to set a new master password afterwards.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final backend = AppBackendScope.of(context);
    final lock = SessionScope.of(context).lock;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      await backend.persistAutoUnlockEnabled(enabled: false);

      final store = SyncConfigStore();
      await store.clearAll();

      await BackgroundSync.refreshSchedule(backend: backend);

      final appDir = await getApplicationSupportDirectory();
      await Directory(appDir.path).delete(recursive: true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Reset failed: $e')));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    lock();
  }

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
            title: const Text('Debug: Reset local data'),
            subtitle:
                const Text('Delete local DB + clear sync/auto-unlock storage'),
            onTap: _busy ? null : _resetLocalData,
          ),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('Debug: Semantic search'),
            subtitle: const Text(
                'Search similar messages + rebuild embeddings index'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const SemanticSearchDebugPage()),
              );
            },
          ),
        ],
      ],
    );
  }
}

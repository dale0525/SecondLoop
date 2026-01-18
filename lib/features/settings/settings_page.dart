import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/background_sync.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import 'llm_profiles_page.dart';
import 'sync_settings_page.dart';
import 'semantic_search_debug_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _appLockEnabled;
  bool? _biometricUnlockEnabled;
  bool _busy = false;

  static const _kAppLockEnabledPrefsKey = 'app_lock_enabled_v1';
  static const _kBiometricUnlockEnabledPrefsKey = 'biometric_unlock_enabled_v1';

  bool _defaultSystemUnlockEnabled() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  Future<void> _resetLocalData() async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset local data?'),
          content: const Text(
            'This will delete local messages and clear synced remote data. '
            'It will NOT delete your master password or local LLM/sync config. '
            'You will need to unlock again.',
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
    final sessionKey = SessionScope.of(context).sessionKey;
    SyncEngineScope.maybeOf(context)?.stop();

    setState(() => _busy = true);
    try {
      final store = SyncConfigStore();
      final sync = await store.loadConfiguredSync();
      if (sync != null) {
        await switch (sync.backendType) {
          SyncBackendType.webdav => backend.syncWebdavClearRemoteRoot(
              baseUrl: sync.baseUrl ?? '',
              username: sync.username,
              password: sync.password,
              remoteRoot: sync.remoteRoot,
            ),
          SyncBackendType.localDir => backend.syncLocaldirClearRemoteRoot(
              localDir: sync.localDir ?? '',
              remoteRoot: sync.remoteRoot,
            ),
        };
      }

      await backend.resetVaultDataPreservingLlmProfiles(sessionKey);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAppLockEnabledPrefsKey);
      await prefs.remove(_kBiometricUnlockEnabledPrefsKey);
      await backend.clearSavedSessionKey();

      await BackgroundSync.refreshSchedule(backend: backend);
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
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kAppLockEnabledPrefsKey) ?? false;
    final biometricEnabled = prefs.getBool(_kBiometricUnlockEnabledPrefsKey) ??
        _defaultSystemUnlockEnabled();
    if (!mounted) return;
    setState(() {
      _appLockEnabled = enabled;
      _biometricUnlockEnabled = biometricEnabled;
    });
  }

  Future<void> _setAppLock(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAppLockEnabledPrefsKey, enabled);
      final biometricEnabled =
          _biometricUnlockEnabled ?? _defaultSystemUnlockEnabled();
      final shouldPersist = !enabled || biometricEnabled;
      if (shouldPersist) {
        await backend.saveSessionKey(sessionKey);
      } else {
        await backend.clearSavedSessionKey();
      }
      await BackgroundSync.refreshSchedule(backend: backend);
      if (mounted) setState(() => _appLockEnabled = enabled);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setBiometricUnlock(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBiometricUnlockEnabledPrefsKey, enabled);

      if (enabled) {
        await backend.saveSessionKey(sessionKey);
      } else {
        await backend.clearSavedSessionKey();
      }

      await BackgroundSync.refreshSchedule(backend: backend);
      if (mounted) setState(() => _biometricUnlockEnabled = enabled);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appLockEnabled ??= false;
    _biometricUnlockEnabled ??= _defaultSystemUnlockEnabled();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _appLockEnabled;
    final biometricEnabled = _biometricUnlockEnabled;
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Auto lock'),
          subtitle: const Text('Require unlock to access the app'),
          value: enabled ?? false,
          onChanged: (_busy || enabled == null) ? null : _setAppLock,
        ),
        if ((enabled ?? false) && (isMobile || isDesktop)) ...[
          const SizedBox(height: 12),
          SwitchListTile(
            title: Text(isMobile ? 'Use biometrics' : 'Use system unlock'),
            subtitle: Text(isMobile
                ? 'Unlock with biometrics instead of master password'
                : 'Unlock with Touch ID / Windows Hello instead of master password'),
            value: biometricEnabled ?? false,
            onChanged: (_busy || biometricEnabled == null)
                ? null
                : _setBiometricUnlock,
          ),
        ],
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
                const Text('Delete local messages + clear synced remote data'),
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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/background_sync.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _localDirController = TextEditingController();
  final _remoteRootController = TextEditingController(text: 'SecondLoop');
  final _syncPassphraseController = TextEditingController();

  bool _busy = false;

  final SyncConfigStore _store = SyncConfigStore();

  SyncBackendType _backendType = SyncBackendType.webdav;
  bool _autoEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _localDirController.dispose();
    _remoteRootController.dispose();
    _syncPassphraseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final backendType = await _store.readBackendType();
    final autoEnabled = await _store.readAutoEnabled();
    final baseUrl = await _store.readWebdavBaseUrl();
    final username = await _store.readWebdavUsername();
    final password = await _store.readWebdavPassword();
    final remoteRoot = await _store.readRemoteRoot();
    final localDir = await _store.readLocalDir();

    if (!mounted) return;
    setState(() {
      _backendType = backendType;
      _autoEnabled = autoEnabled;
      _baseUrlController.text = baseUrl ?? '';
      _usernameController.text = username ?? '';
      _passwordController.text = password ?? '';
      _remoteRootController.text = remoteRoot ?? _remoteRootController.text;
      _localDirController.text = localDir ?? '';
    });
  }

  Future<Uint8List?> _loadSyncKey() async {
    return _store.readSyncKey();
  }

  String _requiredTrimmed(TextEditingController controller) => controller.text.trim();

  String? _optionalTrimmed(TextEditingController controller) {
    final v = controller.text.trim();
    return v.isEmpty ? null : v;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final backend = AppBackendScope.of(context);

      final remoteRoot = _requiredTrimmed(_remoteRootController);
      if (remoteRoot.isEmpty) {
        _showSnack('Remote root is required');
        return;
      }

      await _store.writeBackendType(_backendType);
      await _store.writeAutoEnabled(_autoEnabled);
      await _store.writeRemoteRoot(remoteRoot);

      switch (_backendType) {
        case SyncBackendType.webdav:
          final baseUrl = _requiredTrimmed(_baseUrlController);
          if (baseUrl.isEmpty) {
            _showSnack('Base URL is required');
            return;
          }
          await _store.writeWebdavBaseUrl(baseUrl);
          await _store.writeWebdavUsername(_optionalTrimmed(_usernameController));
          await _store.writeWebdavPassword(_optionalTrimmed(_passwordController));
          break;
        case SyncBackendType.localDir:
          final localDir = _requiredTrimmed(_localDirController);
          if (localDir.isEmpty) {
            _showSnack('Local directory is required');
            return;
          }
          await _store.writeLocalDir(localDir);
          break;
      }

      final passphrase = _optionalTrimmed(_syncPassphraseController);
      if (passphrase != null) {
        final derived = await backend.deriveSyncKey(passphrase);
        await _store.writeSyncKey(derived);
        _syncPassphraseController.clear();
      }

      await BackgroundSync.refreshSchedule(backend: backend);
      _showSnack('Saved');
    } catch (e) {
      _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final backend = AppBackendScope.of(context);
      final remoteRoot = _requiredTrimmed(_remoteRootController);

      switch (_backendType) {
        case SyncBackendType.webdav:
          await backend.syncWebdavTestConnection(
            baseUrl: _requiredTrimmed(_baseUrlController),
            username: _optionalTrimmed(_usernameController),
            password: _optionalTrimmed(_passwordController),
            remoteRoot: remoteRoot,
          );
          break;
        case SyncBackendType.localDir:
          await backend.syncLocaldirTestConnection(
            localDir: _requiredTrimmed(_localDirController),
            remoteRoot: remoteRoot,
          );
          break;
      }
      _showSnack('Connection OK');
    } catch (e) {
      _showSnack('Connection failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;

      final syncKey = await _loadSyncKey();
      if (syncKey == null || syncKey.length != 32) {
        _showSnack('Missing sync key. Enter a passphrase and Save first.');
        return;
      }

      final pushed = switch (_backendType) {
        SyncBackendType.webdav => backend.syncWebdavPush(
            sessionKey,
            syncKey,
            baseUrl: _requiredTrimmed(_baseUrlController),
            username: _optionalTrimmed(_usernameController),
            password: _optionalTrimmed(_passwordController),
            remoteRoot: _requiredTrimmed(_remoteRootController),
          ),
        SyncBackendType.localDir => backend.syncLocaldirPush(
            sessionKey,
            syncKey,
            localDir: _requiredTrimmed(_localDirController),
            remoteRoot: _requiredTrimmed(_remoteRootController),
          ),
      };
      _showSnack('Pushed $pushed ops');
    } catch (e) {
      _showSnack('Push failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pull() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;

      final syncKey = await _loadSyncKey();
      if (syncKey == null || syncKey.length != 32) {
        _showSnack('Missing sync key. Enter a passphrase and Save first.');
        return;
      }

      final pulled = switch (_backendType) {
        SyncBackendType.webdav => backend.syncWebdavPull(
            sessionKey,
            syncKey,
            baseUrl: _requiredTrimmed(_baseUrlController),
            username: _optionalTrimmed(_usernameController),
            password: _optionalTrimmed(_passwordController),
            remoteRoot: _requiredTrimmed(_remoteRootController),
          ),
        SyncBackendType.localDir => backend.syncLocaldirPull(
            sessionKey,
            syncKey,
            localDir: _requiredTrimmed(_localDirController),
            remoteRoot: _requiredTrimmed(_remoteRootController),
          ),
      };
      _showSnack('Pulled $pulled ops');
    } catch (e) {
      _showSnack('Pull failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault Sync'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Auto sync'),
            subtitle: const Text('Foreground debounced push + background periodic sync (mobile)'),
            value: _autoEnabled,
            onChanged: _busy
                ? null
                : (value) async {
                    final backend = AppBackendScope.of(context);
                    setState(() => _autoEnabled = value);
                    await _store.writeAutoEnabled(value);
                    await BackgroundSync.refreshSchedule(backend: backend);
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SyncBackendType>(
            value: _backendType,
            decoration: const InputDecoration(
              labelText: 'Vault backend',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: SyncBackendType.webdav,
                child: Text('WebDAV'),
              ),
              DropdownMenuItem(
                value: SyncBackendType.localDir,
                child: Text('Local directory (desktop)'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _backendType = value);
                  },
          ),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://example.com/dav',
            ),
            enabled: !_busy && _backendType == SyncBackendType.webdav,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username (optional)',
            ),
            enabled: !_busy && _backendType == SyncBackendType.webdav,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password (optional)',
            ),
            enabled: !_busy && _backendType == SyncBackendType.webdav,
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _localDirController,
            decoration: const InputDecoration(
              labelText: 'Local directory path',
              hintText: '/Users/me/SecondLoopVault',
              helperText: 'Best for desktop; mobile platforms may not support this path.',
            ),
            enabled: !_busy && _backendType == SyncBackendType.localDir,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remoteRootController,
            decoration: const InputDecoration(
              labelText: 'Remote root folder',
              hintText: 'SecondLoop',
            ),
            enabled: !_busy,
          ),
          const Divider(height: 24),
          TextField(
            controller: _syncPassphraseController,
            decoration: const InputDecoration(
              labelText: 'Sync passphrase (not stored; derives a key)',
              helperText: 'Use the same passphrase on all devices.',
            ),
            enabled: !_busy,
            obscureText: true,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _testConnection,
            child: const Text('Test connection'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _push,
                  child: const Text('Push'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _pull,
                  child: const Text('Pull'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

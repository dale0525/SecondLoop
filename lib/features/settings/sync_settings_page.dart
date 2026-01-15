import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _remoteRootController = TextEditingController(text: 'SecondLoop');
  final _syncPassphraseController = TextEditingController();

  bool _busy = false;

  late final FlutterSecureStorage _storage = _createDefaultSecureStorage();

  static const _kBaseUrl = 'sync_webdav_base_url';
  static const _kUsername = 'sync_webdav_username';
  static const _kPassword = 'sync_webdav_password';
  static const _kRemoteRoot = 'sync_webdav_remote_root';
  static const _kSyncKeyB64 = 'sync_webdav_sync_key_b64';

  static FlutterSecureStorage _createDefaultSecureStorage() {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return const FlutterSecureStorage(
        mOptions: MacOsOptions(useDataProtectionKeyChain: false),
      );
    }
    return const FlutterSecureStorage();
  }

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
    _remoteRootController.dispose();
    _syncPassphraseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final baseUrl = await _storage.read(key: _kBaseUrl);
    final username = await _storage.read(key: _kUsername);
    final password = await _storage.read(key: _kPassword);
    final remoteRoot = await _storage.read(key: _kRemoteRoot);

    if (!mounted) return;
    setState(() {
      _baseUrlController.text = baseUrl ?? '';
      _usernameController.text = username ?? '';
      _passwordController.text = password ?? '';
      _remoteRootController.text = remoteRoot ?? _remoteRootController.text;
    });
  }

  Future<Uint8List?> _loadSyncKey() async {
    final b64 = await _storage.read(key: _kSyncKeyB64);
    if (b64 == null || b64.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(b64));
    } catch (_) {
      return null;
    }
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

      final baseUrl = _requiredTrimmed(_baseUrlController);
      final remoteRoot = _requiredTrimmed(_remoteRootController);
      if (baseUrl.isEmpty) {
        _showSnack('Base URL is required');
        return;
      }
      if (remoteRoot.isEmpty) {
        _showSnack('Remote root is required');
        return;
      }

      await _storage.write(key: _kBaseUrl, value: baseUrl);
      await _storage.write(key: _kRemoteRoot, value: remoteRoot);

      final username = _optionalTrimmed(_usernameController);
      final password = _optionalTrimmed(_passwordController);
      if (username == null) {
        await _storage.delete(key: _kUsername);
      } else {
        await _storage.write(key: _kUsername, value: username);
      }
      if (password == null) {
        await _storage.delete(key: _kPassword);
      } else {
        await _storage.write(key: _kPassword, value: password);
      }

      final passphrase = _optionalTrimmed(_syncPassphraseController);
      if (passphrase != null) {
        final derived = await backend.deriveSyncKey(passphrase);
        await _storage.write(key: _kSyncKeyB64, value: base64Encode(derived));
        _syncPassphraseController.clear();
      }

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
      final baseUrl = _requiredTrimmed(_baseUrlController);
      final remoteRoot = _requiredTrimmed(_remoteRootController);

      await backend.syncWebdavTestConnection(
        baseUrl: baseUrl,
        username: _optionalTrimmed(_usernameController),
        password: _optionalTrimmed(_passwordController),
        remoteRoot: remoteRoot,
      );
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

      final pushed = await backend.syncWebdavPush(
        sessionKey,
        syncKey,
        baseUrl: _requiredTrimmed(_baseUrlController),
        username: _optionalTrimmed(_usernameController),
        password: _optionalTrimmed(_passwordController),
        remoteRoot: _requiredTrimmed(_remoteRootController),
      );
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

      final pulled = await backend.syncWebdavPull(
        sessionKey,
        syncKey,
        baseUrl: _requiredTrimmed(_baseUrlController),
        username: _optionalTrimmed(_usernameController),
        password: _optionalTrimmed(_passwordController),
        remoteRoot: _requiredTrimmed(_remoteRootController),
      );
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
        title: const Text('Sync (WebDAV)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://example.com/dav',
            ),
            enabled: !_busy,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username (optional)',
            ),
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password (optional)',
            ),
            enabled: !_busy,
            obscureText: true,
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

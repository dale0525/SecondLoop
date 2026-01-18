import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/background_sync.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({
    super.key,
    this.configStore,
  });

  final SyncConfigStore? configStore;

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  static const _kPassphrasePlaceholder = '********';

  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _localDirController = TextEditingController();
  final _remoteRootController = TextEditingController(text: 'SecondLoop');
  final _syncPassphraseController = TextEditingController();

  bool _busy = false;
  bool _passphraseIsPlaceholder = false;

  late final SyncConfigStore _store = widget.configStore ?? SyncConfigStore();

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
    final all = await _store.readAll();
    final backendType = switch (all[SyncConfigStore.kBackendType]) {
      'localdir' => SyncBackendType.localDir,
      _ => SyncBackendType.webdav,
    };
    final autoValue = all[SyncConfigStore.kAutoEnabled];
    final autoEnabled = autoValue == null ? true : autoValue == '1';
    final baseUrl = all[SyncConfigStore.kWebdavBaseUrl];
    final username = all[SyncConfigStore.kWebdavUsername];
    final password = all[SyncConfigStore.kWebdavPassword];
    final remoteRoot = all[SyncConfigStore.kRemoteRoot];
    final localDir = all[SyncConfigStore.kLocalDir];
    final hasSyncKey = (all[SyncConfigStore.kSyncKeyB64] ?? '').isNotEmpty;

    if (!mounted) return;
    setState(() {
      _backendType = backendType;
      _autoEnabled = autoEnabled;
      _baseUrlController.text = baseUrl ?? '';
      _usernameController.text = username ?? '';
      _passwordController.text = password ?? '';
      _remoteRootController.text = remoteRoot ?? _remoteRootController.text;
      _localDirController.text = localDir ?? '';
      if (hasSyncKey) {
        _syncPassphraseController.text = _kPassphrasePlaceholder;
        _passphraseIsPlaceholder = true;
      }
    });
  }

  Future<Uint8List?> _loadSyncKey() async {
    return _store.readSyncKey();
  }

  String _requiredTrimmed(TextEditingController controller) =>
      controller.text.trim();

  String? _optionalTrimmed(TextEditingController controller) {
    final v = controller.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<bool> _persistBackendConfig() async {
    final t = context.t;
    final remoteRoot = _requiredTrimmed(_remoteRootController);
    if (remoteRoot.isEmpty) {
      _showSnack(t.sync.remoteRootRequired);
      return false;
    }

    await _store.writeBackendType(_backendType);
    await _store.writeAutoEnabled(_autoEnabled);
    await _store.writeRemoteRoot(remoteRoot);

    switch (_backendType) {
      case SyncBackendType.webdav:
        final baseUrl = _requiredTrimmed(_baseUrlController);
        if (baseUrl.isEmpty) {
          _showSnack(t.sync.baseUrlRequired);
          return false;
        }
        await _store.writeWebdavBaseUrl(baseUrl);
        await _store.writeWebdavUsername(_optionalTrimmed(_usernameController));
        await _store.writeWebdavPassword(_optionalTrimmed(_passwordController));
        break;
      case SyncBackendType.localDir:
        final localDir = _requiredTrimmed(_localDirController);
        if (localDir.isEmpty) {
          _showSnack(t.sync.localDirRequired);
          return false;
        }
        await _store.writeLocalDir(localDir);
        break;
    }

    return true;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runConnectionTest() async {
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
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);

    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);

      final persisted = await _persistBackendConfig();
      if (!persisted) return;

      final passphrase = _optionalTrimmed(_syncPassphraseController);
      if (passphrase != null && !_passphraseIsPlaceholder) {
        final derived = await backend.deriveSyncKey(passphrase);
        await _store.writeSyncKey(derived);
        _syncPassphraseController.text = _kPassphrasePlaceholder;
        _passphraseIsPlaceholder = true;
      }

      unawaited(BackgroundSync.refreshSchedule(
          backend: backend, configStore: _store));

      try {
        await _runConnectionTest();
        if (!mounted) return;
        _showSnack(t.sync.connectionOk);
        final engine = SyncEngineScope.maybeOf(context);
        engine?.start();
        engine?.triggerPullNow();
        engine?.triggerPushNow();
      } catch (e) {
        if (!mounted) return;
        _showSnack(t.sync.connectionFailed(error: '$e'));
      }
    } catch (e) {
      _showSnack(t.sync.saveFailed(error: '$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push() async {
    if (_busy) return;
    setState(() => _busy = true);

    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;

      final persisted = await _persistBackendConfig();
      if (!persisted) return;

      final syncKey = await _loadSyncKey();
      if (syncKey == null || syncKey.length != 32) {
        _showSnack(t.sync.missingSyncKey);
        return;
      }

      final pushed = await (switch (_backendType) {
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
      });
      _showSnack(t.sync.pushedOps(count: pushed));
    } catch (e) {
      _showSnack(t.sync.pushFailed(error: '$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pull() async {
    if (_busy) return;
    setState(() => _busy = true);

    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;

      final persisted = await _persistBackendConfig();
      if (!persisted) return;

      final syncKey = await _loadSyncKey();
      if (syncKey == null || syncKey.length != 32) {
        _showSnack(t.sync.missingSyncKey);
        return;
      }

      final pulled = await (switch (_backendType) {
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
      });
      _showSnack(t.sync.pulledOps(count: pulled));
    } catch (e) {
      _showSnack(t.sync.pullFailed(error: '$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget sectionTitle(String title) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    }

    Widget sectionCard(Widget child) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.sync.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          sectionTitle(context.t.sync.sections.automation),
          sectionCard(
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.t.sync.autoSync.title),
              subtitle: Text(context.t.sync.autoSync.subtitle),
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
          ),
          const SizedBox(height: 16),
          sectionTitle(context.t.sync.sections.backend),
          sectionCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<SyncBackendType>(
                  value: _backendType,
                  decoration: InputDecoration(
                    labelText: context.t.sync.backendLabel,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: SyncBackendType.webdav,
                      child: Text(context.t.sync.backendWebdav),
                    ),
                    DropdownMenuItem(
                      value: SyncBackendType.localDir,
                      child: Text(context.t.sync.backendLocalDir),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _backendType = value);
                        },
                ),
                const SizedBox(height: 12),
                if (_backendType == SyncBackendType.webdav) ...[
                  TextField(
                    controller: _baseUrlController,
                    decoration: InputDecoration(
                      labelText: context.t.sync.fields.baseUrl.label,
                      hintText: context.t.sync.fields.baseUrl.hint,
                    ),
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: context.t.sync.fields.username.label,
                    ),
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: context.t.sync.fields.password.label,
                    ),
                    enabled: !_busy,
                    obscureText: true,
                    obscuringCharacter: '*',
                  ),
                  const SizedBox(height: 12),
                ],
                if (_backendType == SyncBackendType.localDir) ...[
                  TextField(
                    controller: _localDirController,
                    decoration: InputDecoration(
                      labelText: context.t.sync.fields.localDir.label,
                      hintText: context.t.sync.fields.localDir.hint,
                      helperText: context.t.sync.fields.localDir.helper,
                    ),
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _remoteRootController,
                  decoration: InputDecoration(
                    labelText: context.t.sync.fields.remoteRoot.label,
                    hintText: context.t.sync.fields.remoteRoot.hint,
                  ),
                  enabled: !_busy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          sectionTitle(context.t.sync.sections.securityActions),
          sectionCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _syncPassphraseController,
                  decoration: InputDecoration(
                    labelText: context.t.sync.fields.passphrase.label,
                    helperText: context.t.sync.fields.passphrase.helper,
                  ),
                  enabled: !_busy,
                  obscureText: true,
                  obscuringCharacter: '*',
                  onTap: _passphraseIsPlaceholder
                      ? () {
                          _syncPassphraseController.clear();
                          setState(() => _passphraseIsPlaceholder = false);
                        }
                      : null,
                  onChanged: (_) {
                    if (!_passphraseIsPlaceholder) return;
                    setState(() => _passphraseIsPlaceholder = false);
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(context.t.common.actions.save),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _push,
                        child: Text(context.t.common.actions.push),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _pull,
                        child: Text(context.t.common.actions.pull),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

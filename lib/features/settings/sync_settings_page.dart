import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/sync/cloud_sync_switch_prefs.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/background_sync.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import '../media_backup/cloud_media_backup_runner.dart';

part 'sync_settings_page_media_actions.dart';
part 'sync_settings_page_sync_actions.dart';

enum _ManualSyncAction {
  push,
  pull,
}

String _formatTimestamp(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}

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
  static const _kSaveSyncProgressKey = ValueKey('sync_save_progress');
  static const _kSaveSyncProgressPercentKey =
      ValueKey('sync_save_progress_percent');

  final _baseUrlController = TextEditingController();
  final _managedVaultBaseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _localDirController = TextEditingController();
  final _remoteRootController = TextEditingController(text: 'SecondLoop');
  final _syncPassphraseController = TextEditingController();

  bool _busy = false;
  _ManualSyncAction? _manualSyncAction;
  double? _manualSyncProgress;
  bool _manualSyncHasTotal = false;
  bool _passphraseIsPlaceholder = false;
  bool _showManagedVaultEndpointOverride = false;

  late final SyncConfigStore _store = widget.configStore ?? SyncConfigStore();

  SyncBackendType _backendType = SyncBackendType.webdav;
  bool _autoEnabled = true;
  bool _autoWifiOnly = false;
  bool _mediaDownloadsWifiOnly = true;
  bool _cloudMediaBackupEnabled = true;
  bool _cloudMediaBackupWifiOnly = true;
  Future<CloudMediaBackupSummary>? _cloudMediaBackupSummary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _managedVaultBaseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _localDirController.dispose();
    _remoteRootController.dispose();
    _syncPassphraseController.dispose();
    super.dispose();
  }

  Future<CloudMediaBackupSummary>? _maybeLoadCloudMediaBackupSummary() {
    final backendScope =
        context.getInheritedWidgetOfExactType<AppBackendScope>();
    final sessionScope = context.getInheritedWidgetOfExactType<SessionScope>();
    if (backendScope == null || sessionScope == null) return null;
    try {
      return backendScope.backend
          .cloudMediaBackupSummary(sessionScope.sessionKey);
    } on UnimplementedError {
      return null;
    }
  }

  void _refreshCloudMediaBackupSummary() {
    if (!mounted) return;
    setState(() {
      _cloudMediaBackupSummary = _maybeLoadCloudMediaBackupSummary();
    });
  }

  Future<void> _load() async {
    final all = await _store.readAll();
    final backendType = switch (all[SyncConfigStore.kBackendType]) {
      'localdir' => SyncBackendType.localDir,
      'managedvault' => SyncBackendType.managedVault,
      _ => SyncBackendType.webdav,
    };
    final autoValue = all[SyncConfigStore.kAutoEnabled];
    final autoEnabled = autoValue == null ? true : autoValue == '1';
    final autoWifiOnly = (all[SyncConfigStore.kAutoWifiOnly] ?? '0') == '1';
    final baseUrl = all[SyncConfigStore.kWebdavBaseUrl];
    final managedVaultBaseUrl = all[SyncConfigStore.kManagedVaultBaseUrl];
    final username = all[SyncConfigStore.kWebdavUsername];
    final password = all[SyncConfigStore.kWebdavPassword];
    final remoteRoot = all[SyncConfigStore.kRemoteRoot];
    final localDir = all[SyncConfigStore.kLocalDir];
    final hasSyncKey = (all[SyncConfigStore.kSyncKeyB64] ?? '').isNotEmpty;
    final mediaDownloadsWifiOnly =
        (all[SyncConfigStore.kMediaDownloadsWifiOnly] ?? '1') == '1';
    final cloudMediaBackupEnabled =
        (all[SyncConfigStore.kCloudMediaBackupEnabled] ?? '1') == '1';
    final cloudMediaBackupWifiOnly =
        (all[SyncConfigStore.kCloudMediaBackupWifiOnly] ?? '1') == '1';

    if (!mounted) return;
    setState(() {
      _backendType = backendType;
      _autoEnabled = autoEnabled;
      _autoWifiOnly = autoWifiOnly;
      _baseUrlController.text = baseUrl ?? '';
      _managedVaultBaseUrlController.text = managedVaultBaseUrl ?? '';
      _usernameController.text = username ?? '';
      _passwordController.text = password ?? '';
      _remoteRootController.text = remoteRoot ?? _remoteRootController.text;
      _localDirController.text = localDir ?? '';
      _mediaDownloadsWifiOnly = mediaDownloadsWifiOnly;
      _cloudMediaBackupEnabled = cloudMediaBackupEnabled;
      _cloudMediaBackupWifiOnly = cloudMediaBackupWifiOnly;
      _cloudMediaBackupSummary = (backendType == SyncBackendType.managedVault ||
              backendType == SyncBackendType.webdav)
          ? _maybeLoadCloudMediaBackupSummary()
          : null;
      if (hasSyncKey) {
        _syncPassphraseController.text = _kPassphrasePlaceholder;
        _passphraseIsPlaceholder = true;
      }
    });
  }

  Future<Uint8List?> _loadSyncKey() async {
    return _store.readSyncKey();
  }

  void _setState(VoidCallback fn) => setState(fn);

  String _requiredTrimmed(TextEditingController controller) =>
      controller.text.trim();

  String? _optionalTrimmed(TextEditingController controller) {
    final v = controller.text.trim();
    return v.isEmpty ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final engine = SyncEngineScope.maybeOf(context);
    final cloudUid = CloudAuthScope.maybeOf(context)?.controller.uid?.trim();
    if (_backendType == SyncBackendType.managedVault &&
        cloudUid != null &&
        cloudUid.isNotEmpty &&
        _remoteRootController.text != cloudUid) {
      _remoteRootController.text = cloudUid;
    }

    final canClearLocalCache = switch (_backendType) {
      SyncBackendType.webdav =>
        _requiredTrimmed(_baseUrlController).isNotEmpty &&
            _requiredTrimmed(_remoteRootController).isNotEmpty,
      SyncBackendType.managedVault => cloudUid != null && cloudUid.isNotEmpty,
      _ => false,
    };

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
      return SlSurface(
        padding: const EdgeInsets.all(12),
        child: child,
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
            Column(
              children: [
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
                          await BackgroundSync.refreshSchedule(
                              backend: backend);
                        },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const ValueKey('sync_auto_wifi_only'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.t.sync.autoSync.wifiOnlyTitle),
                  subtitle: Text(context.t.sync.autoSync.wifiOnlySubtitle),
                  value: _autoWifiOnly,
                  onChanged: _busy
                      ? null
                      : (value) async {
                          await _setAutoWifiOnly(value);
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onLongPress:
                (_backendType == SyncBackendType.managedVault && kDebugMode)
                    ? () {
                        setState(() {
                          _showManagedVaultEndpointOverride =
                              !_showManagedVaultEndpointOverride;
                        });
                      }
                    : null,
            child: sectionTitle(context.t.sync.sections.backend),
          ),
          sectionCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (engine != null)
                  ValueListenableBuilder(
                    valueListenable: engine.writeGate,
                    builder: (context, gate, _) {
                      if (_backendType != SyncBackendType.managedVault) {
                        return const SizedBox.shrink();
                      }
                      if (gate.kind == SyncWriteGateKind.open) {
                        return const SizedBox.shrink();
                      }

                      final nowMs = DateTime.now().millisecondsSinceEpoch;
                      final untilMs = gate.graceUntilMs;
                      final activeGrace =
                          gate.kind == SyncWriteGateKind.graceReadOnly &&
                              untilMs != null &&
                              nowMs < untilMs;

                      if (gate.kind == SyncWriteGateKind.graceReadOnly &&
                          activeGrace) {
                        final dt = DateTime.fromMillisecondsSinceEpoch(untilMs)
                            .toLocal();
                        final until = MaterialLocalizations.of(context)
                            .formatShortDate(dt);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            context.t.sync.cloudManagedVault
                                .graceReadonlyUntil(until: until),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: Theme.of(context).colorScheme.error),
                          ),
                        );
                      }

                      if (gate.kind == SyncWriteGateKind.paymentRequired) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            context.t.sync.cloudManagedVault.paymentRequired,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: Theme.of(context).colorScheme.error),
                          ),
                        );
                      }

                      if (gate.kind == SyncWriteGateKind.storageQuotaExceeded) {
                        final used = gate.quotaUsedBytes;
                        final limit = gate.quotaLimitBytes;
                        final message =
                            (used != null && limit != null && limit > 0)
                                ? context.t.sync.cloudManagedVault
                                    .storageQuotaExceededWithUsage(
                                    used: _formatBytes(used),
                                    limit: _formatBytes(limit),
                                  )
                                : context.t.sync.cloudManagedVault
                                    .storageQuotaExceeded;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            message,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: Theme.of(context).colorScheme.error),
                          ),
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
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
                    DropdownMenuItem(
                      value: SyncBackendType.managedVault,
                      child: Text(context.t.sync.backendManagedVault),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _backendType = value;
                            _cloudMediaBackupSummary =
                                value == SyncBackendType.managedVault
                                    ? _maybeLoadCloudMediaBackupSummary()
                                    : null;
                          });
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
                if (_backendType == SyncBackendType.managedVault &&
                    kDebugMode &&
                    _showManagedVaultEndpointOverride) ...[
                  TextField(
                    controller: _managedVaultBaseUrlController,
                    decoration: InputDecoration(
                      labelText:
                          context.t.sync.fields.managedVaultBaseUrl.label,
                      hintText: context.t.sync.fields.managedVaultBaseUrl.hint,
                    ),
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _remoteRootController,
                  decoration: InputDecoration(
                    labelText: _backendType == SyncBackendType.managedVault
                        ? context.t.sync.fields.vaultId.label
                        : context.t.sync.fields.remoteRoot.label,
                    hintText: _backendType == SyncBackendType.managedVault
                        ? context.t.sync.fields.vaultId.hint
                        : context.t.sync.fields.remoteRoot.hint,
                  ),
                  enabled: _backendType == SyncBackendType.managedVault
                      ? false
                      : !_busy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          sectionTitle(context.t.sync.sections.mediaPreview),
          sectionCard(
            SwitchListTile(
              key: const ValueKey('sync_media_downloads_wifi_only'),
              contentPadding: EdgeInsets.zero,
              title:
                  Text(context.t.sync.mediaPreview.chatThumbnailsWifiOnlyTitle),
              subtitle: Text(
                  context.t.sync.mediaPreview.chatThumbnailsWifiOnlySubtitle),
              value: _mediaDownloadsWifiOnly,
              onChanged: _busy
                  ? null
                  : (value) async {
                      await _setMediaDownloadsWifiOnly(value);
                    },
            ),
          ),
          const SizedBox(height: 16),
          if (_backendType == SyncBackendType.managedVault ||
              _backendType == SyncBackendType.webdav) ...[
            sectionTitle(context.t.sync.sections.mediaBackup),
            sectionCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    key: const ValueKey('sync_media_backup_enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.t.sync.mediaBackup.title),
                    subtitle: Text(context.t.sync.mediaBackup.subtitle),
                    value: _cloudMediaBackupEnabled,
                    onChanged: _busy
                        ? null
                        : (value) async {
                            await _setCloudMediaBackupEnabled(value);
                          },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('sync_media_backup_wifi_only'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.t.sync.mediaBackup.wifiOnlyTitle),
                    subtitle: Text(context.t.sync.mediaBackup.wifiOnlySubtitle),
                    value: _cloudMediaBackupWifiOnly,
                    onChanged: _busy || !_cloudMediaBackupEnabled
                        ? null
                        : (value) async {
                            await _setCloudMediaBackupWifiOnly(value);
                          },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.t.sync.mediaBackup.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder(
                    future: _cloudMediaBackupSummary,
                    builder: (context, snapshot) {
                      final s = snapshot.data;
                      if (s == null) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox.shrink();
                        }
                        return const SizedBox.shrink();
                      }

                      final lastUploaded = s.lastUploadedAtMs;
                      final lastError = s.lastError;
                      final lastErrorAtMs = s.lastErrorAtMs;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.t.sync.mediaBackup.stats(
                              pending: s.pending,
                              failed: s.failed,
                              uploaded: s.uploaded,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (lastUploaded != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              context.t.sync.mediaBackup.lastUploaded(
                                at: _formatTimestamp(lastUploaded),
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (lastError != null &&
                              lastError.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    lastErrorAtMs == null
                                        ? context.t.sync.mediaBackup
                                            .lastError(error: lastError)
                                        : context.t.sync.mediaBackup
                                            .lastErrorWithTime(
                                            error: lastError,
                                            at: _formatTimestamp(lastErrorAtMs),
                                          ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error),
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.t.common.actions.copy,
                                  onPressed: () => _copyText(lastError),
                                  icon: const Icon(Icons.copy_rounded),
                                ),
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy || !_cloudMediaBackupEnabled
                              ? null
                              : _backfillCloudMediaBackupImages,
                          child:
                              Text(context.t.sync.mediaBackup.backfillButton),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy || !_cloudMediaBackupEnabled
                              ? null
                              : _uploadCloudMediaBackupNow,
                          child:
                              Text(context.t.sync.mediaBackup.uploadNowButton),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
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
                    helperMaxLines: 3,
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
                if (_backendType == SyncBackendType.managedVault &&
                    (cloudUid == null || cloudUid.isEmpty))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      context.t.sync.cloudManagedVault.signInRequired,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Builder(
                  builder: (context) {
                    final active = _manualSyncAction != null;
                    final progressValue = _manualSyncProgress;
                    final percentText = progressValue == null
                        ? ''
                        : '${(progressValue * 100).floor().clamp(0, 100)}%';

                    return SizedBox(
                      height: active ? 24 : 4,
                      child: !active
                          ? const SizedBox.shrink()
                          : Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 4,
                                    child: LinearProgressIndicator(
                                      key: const ValueKey(
                                          'sync_manual_progress'),
                                      value: progressValue,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    percentText,
                                    key: const ValueKey(
                                        'sync_manual_progress_percent'),
                                    textAlign: TextAlign.right,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
                if (engine == null)
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
                  )
                else
                  ValueListenableBuilder(
                    valueListenable: engine.writeGate,
                    builder: (context, gate, _) {
                      final disablePush = _busy ||
                          (_backendType == SyncBackendType.managedVault &&
                              gate.kind != SyncWriteGateKind.open);
                      final disablePull = _busy ||
                          (_backendType == SyncBackendType.managedVault &&
                              gate.kind == SyncWriteGateKind.paymentRequired);

                      return Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: disablePush ? null : _push,
                              child: Text(context.t.common.actions.push),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: disablePull ? null : _pull,
                              child: Text(context.t.common.actions.pull),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy || !canClearLocalCache
                      ? null
                      : _clearLocalAttachmentCache,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(context.t.sync.localCache.button),
                ),
                const SizedBox(height: 6),
                Text(
                  context.t.sync.localCache.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

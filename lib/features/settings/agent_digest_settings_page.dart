import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/secretary_backend.dart';
import '../../core/cloud/agent_digest_client.dart';
import '../../core/cloud/cloud_auth_access.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/secretary/rule_based_planning_engine.dart';
import '../../core/secretary/secretary_controller.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import 'package:secondloop/core/models/app_models.dart';
import '../../ui/sl_surface.dart';
import '../../web_app/web_formal_settings_scope.dart';

typedef AgentDigestTodosLoader = Future<List<Todo>> Function(Uint8List key);
typedef AgentDigestDeviceIdLoader = Future<String> Function();

final class AgentDigestPrefs {
  const AgentDigestPrefs._();

  static const prefsKey = 'agent_digest_enabled_v1';

  static Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, enabled);
  }
}

class AgentDigestSettingsPage extends StatefulWidget {
  const AgentDigestSettingsPage({
    super.key,
    this.api,
    this.configStore,
    this.secretaryController,
    this.todosLoader,
    this.deviceIdLoader,
    this.nowMsProvider,
  });

  final AgentDigestApi? api;
  final SyncConfigStore? configStore;
  final SecretaryController? secretaryController;
  final AgentDigestTodosLoader? todosLoader;
  final AgentDigestDeviceIdLoader? deviceIdLoader;
  final int Function()? nowMsProvider;

  @override
  State<AgentDigestSettingsPage> createState() =>
      _AgentDigestSettingsPageState();
}

class _AgentDigestSettingsPageState extends State<AgentDigestSettingsPage> {
  AgentDigestApi? _ownedApi;
  SyncConfigStore? _fallbackStore;
  AgentDigestMeta _meta = const AgentDigestMeta.empty();
  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;
  String? _statusMessage;

  AgentDigestApi get _api => widget.api ?? (_ownedApi ??= AgentDigestClient());

  SyncConfigStore _store(BuildContext context) {
    final explicit = widget.configStore;
    if (explicit != null) return explicit;
    final webStore =
        WebFormalSettingsScope.maybeOf(context)?.dependencies.vaultConfigStore;
    if (webStore != null) return webStore;
    return _fallbackStore ??= SyncConfigStore();
  }

  int _nowMs() =>
      widget.nowMsProvider?.call() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    final api = _ownedApi;
    if (api is AgentDigestClient) {
      api.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      final enabled = await AgentDigestPrefs.loadEnabled();
      final target = await _resolveTarget(interactive: false);
      AgentDigestMeta meta = const AgentDigestMeta.empty();
      if (target != null) {
        meta = await _api.fetchMeta(
          managedVaultBaseUrl: target.managedVaultBaseUrl,
          vaultId: target.vaultId,
          idToken: target.idToken,
        );
      }
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _meta = meta;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = context.t.settings.agentDigest.messages.loadFailed(
          error: '$error',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<_AgentDigestTarget?> _resolveTarget(
      {required bool interactive}) async {
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    if (subscriptionStatus != SubscriptionStatus.entitled) return null;

    final cloudAuth = CloudAuthScope.maybeOf(context)?.controller;
    final cloudUid = cloudAuth?.uid?.trim();
    final store = _store(context);
    final idToken = await readCloudAuthIdToken(
      cloudAuth,
      mode: interactive
          ? CloudAuthAccessMode.interactive
          : CloudAuthAccessMode.background,
    );
    if (idToken == null || idToken.trim().isEmpty) return null;

    final backendType = await store.readBackendType();
    if (backendType != SyncBackendType.managedVault) return null;
    final baseUrl = await store.resolveManagedVaultBaseUrl();
    if (baseUrl == null || baseUrl.trim().isEmpty) return null;
    final remoteRoot = (await store.readRemoteRoot())?.trim();
    final vaultId =
        (remoteRoot != null && remoteRoot.isNotEmpty) ? remoteRoot : cloudUid;
    if (vaultId == null || vaultId.isEmpty) return null;

    return _AgentDigestTarget(
      managedVaultBaseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
    );
  }

  Future<void> _confirmRegenerate() async {
    final confirmed = await _confirm(
      title: context.t.settings.agentDigest.dialogs.regenerate.title,
      body: context.t.settings.agentDigest.dialogs.regenerate.body,
      confirmLabel: context.t.settings.agentDigest.actions.regenerate,
      confirmKey: const ValueKey('agent_digest_confirm_upload'),
    );
    if (confirmed) {
      await _regenerate();
    }
  }

  Future<void> _regenerate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });

    try {
      final key = SessionScope.of(context).sessionKey;
      final controller = _secretaryController();
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      final nowMs = _nowMs();
      final target = await _resolveTarget(interactive: true);
      if (target == null) {
        throw StateError('agent_digest_cloud_not_ready');
      }
      final todos = await _loadTodos(key);
      final deviceId = await _loadDeviceId();
      final digest = await controller.buildAgentDigest(
        key,
        todos: todos,
        deviceId: deviceId,
        localeTag: localeTag,
        nowMs: nowMs,
      );
      final meta = await _api.uploadDigest(
        managedVaultBaseUrl: target.managedVaultBaseUrl,
        vaultId: target.vaultId,
        idToken: target.idToken,
        digest: digest.toJson(),
      );
      await AgentDigestPrefs.setEnabled(true);
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _meta = meta;
        _statusMessage = context.t.settings.agentDigest.messages.uploaded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = context.t.settings.agentDigest.messages.uploadFailed(
          error: '$error',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pause() async {
    final confirmed = await _confirm(
      title: context.t.settings.agentDigest.dialogs.pause.title,
      body: context.t.settings.agentDigest.dialogs.pause.body,
      confirmLabel: context.t.settings.agentDigest.actions.pause,
    );
    if (!confirmed) return;
    await AgentDigestPrefs.setEnabled(false);
    if (!mounted) return;
    setState(() {
      _enabled = false;
      _statusMessage = context.t.settings.agentDigest.messages.paused;
    });
  }

  Future<void> _delete() async {
    final confirmed = await _confirm(
      title: context.t.settings.agentDigest.dialogs.delete.title,
      body: context.t.settings.agentDigest.dialogs.delete.body,
      confirmLabel: context.t.settings.agentDigest.actions.delete,
    );
    if (!confirmed || _busy) return;

    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final target = await _resolveTarget(interactive: true);
      if (target == null) {
        throw StateError('agent_digest_cloud_not_ready');
      }
      await _api.deleteDigest(
        managedVaultBaseUrl: target.managedVaultBaseUrl,
        vaultId: target.vaultId,
        idToken: target.idToken,
      );
      await AgentDigestPrefs.setEnabled(false);
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _meta = const AgentDigestMeta.empty();
        _statusMessage = context.t.settings.agentDigest.messages.deleted;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = context.t.settings.agentDigest.messages.deleteFailed(
          error: '$error',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    Key? confirmKey,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton(
              key: confirmKey,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  SecretaryController _secretaryController() {
    final explicit = widget.secretaryController;
    if (explicit != null) return explicit;

    final backend = AppBackendScope.of(context);
    if (backend is! SecretaryBackend) {
      throw StateError('secretary_backend_required');
    }
    return SecretaryController(
      backend: backend as SecretaryBackend,
      planningEngine: const RuleBasedPlanningEngine(nowLocal: DateTime.now),
    );
  }

  Future<List<Todo>> _loadTodos(Uint8List key) {
    final loader = widget.todosLoader;
    if (loader != null) return loader(key);
    return AppBackendScope.of(context).listTodos(key);
  }

  Future<String> _loadDeviceId() {
    final loader = widget.deviceIdLoader;
    if (loader != null) return loader();
    return AppBackendScope.of(context).getOrCreateDeviceId();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.agentDigest;
    final theme = Theme.of(context);
    final statusLabel = _enabled ? t.status.enabled : t.status.paused;
    final targetReady = SubscriptionScope.maybeOf(context)?.status ==
        SubscriptionStatus.entitled;

    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SlSurface(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _enabled ? Icons.cloud_done : Icons.cloud_off,
                        color: _enabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statusLabel,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              targetReady ? t.subtitle : t.requiresCloud,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SlSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _InfoTile(
                  label: t.fields.lastGenerated,
                  value: _meta.generatedAtMs == null
                      ? t.values.never
                      : _formatTimestamp(_meta.generatedAtMs!),
                ),
                const Divider(height: 1),
                _InfoTile(
                  label: t.fields.size,
                  value: _meta.byteLen == null
                      ? t.values.none
                      : _formatBytes(_meta.byteLen!),
                ),
                const Divider(height: 1),
                _InfoTile(
                  label: t.fields.device,
                  value: _meta.deviceId ?? t.values.unknownDevice,
                ),
                const Divider(height: 1),
                _InfoTile(
                  label: t.fields.version,
                  value: _meta.version ?? t.values.none,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t.privacyNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                key: const ValueKey('agent_digest_regenerate'),
                onPressed: _busy ? null : _confirmRegenerate,
                icon: const Icon(Icons.refresh),
                label: Text(t.actions.regenerate),
              ),
              OutlinedButton.icon(
                key: const ValueKey('agent_digest_pause'),
                onPressed: (_busy || !_enabled) ? null : _pause,
                icon: const Icon(Icons.pause_circle_outline),
                label: Text(t.actions.pause),
              ),
              OutlinedButton.icon(
                key: const ValueKey('agent_digest_delete'),
                onPressed: (_busy || !_meta.exists) ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: Text(t.actions.delete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          value,
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _AgentDigestTarget {
  const _AgentDigestTarget({
    required this.managedVaultBaseUrl,
    required this.vaultId,
    required this.idToken,
  });

  final String managedVaultBaseUrl;
  final String vaultId;
  final String idToken;
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
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

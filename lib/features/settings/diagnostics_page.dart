import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/native_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_capability_auth.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_diagnostics.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/update/update_event_log.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/api/sync_diagnostics.dart' as rust_sync_diagnostics;

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Future<String>? _jsonFuture;
  bool _busy = false;

  String _backendTypeToken(SyncBackendType backendType) {
    return switch (backendType) {
      SyncBackendType.webdav => 'webdav',
      SyncBackendType.localDir => 'localdir',
      SyncBackendType.managedVault => 'managedvault',
    };
  }

  Map<String, Object?> _syncResultToDiagnosticsJson(
      SyncBackgroundResult result) {
    final localTime = DateTime.fromMillisecondsSinceEpoch(result.timestampMs);
    return <String, Object?>{
      ...result.toJson(),
      'timestampLocal': localTime.toIso8601String(),
      'timestampUtc': localTime.toUtc().toIso8601String(),
    };
  }

  Map<String, Object?> _syncBackoffToDiagnosticsJson(
    SyncBackgroundBackoffState state,
  ) {
    final nextAllowedLocal =
        DateTime.fromMillisecondsSinceEpoch(state.nextAllowedAtMs);
    final updatedLocal = DateTime.fromMillisecondsSinceEpoch(state.updatedAtMs);
    return <String, Object?>{
      ...state.toJson(),
      'nextAllowedAtLocal': nextAllowedLocal.toIso8601String(),
      'nextAllowedAtUtc': nextAllowedLocal.toUtc().toIso8601String(),
      'updatedAtLocal': updatedLocal.toIso8601String(),
      'updatedAtUtc': updatedLocal.toUtc().toIso8601String(),
    };
  }

  Future<Map<String, Object?>> _buildSyncDiagnostics() async {
    final store = SyncConfigStore();
    final syncLogsByBackend = <String, Object?>{};
    final syncBackoffByBackend = <String, Object?>{};
    SyncBackgroundResult? latestSyncLog;

    for (final backendType in SyncBackendType.values) {
      final token = _backendTypeToken(backendType);
      final log =
          await store.readBackgroundSyncResult(backendType: backendType);
      if (log != null) {
        syncLogsByBackend[token] = _syncResultToDiagnosticsJson(log);
        if (latestSyncLog == null ||
            log.timestampMs > latestSyncLog.timestampMs) {
          latestSyncLog = log;
        }
      }

      final backoff =
          await store.readBackgroundSyncBackoffState(backendType: backendType);
      if (backoff != null) {
        syncBackoffByBackend[token] = _syncBackoffToDiagnosticsJson(backoff);
      }
    }

    return <String, Object?>{
      'last_sync_log': latestSyncLog == null
          ? null
          : _syncResultToDiagnosticsJson(latestSyncLog),
      'sync_logs_by_backend':
          syncLogsByBackend.isEmpty ? null : syncLogsByBackend,
      'sync_backoff_by_backend':
          syncBackoffByBackend.isEmpty ? null : syncBackoffByBackend,
    };
  }

  Map<String, Object?> _toStringKeyMap(Map<Object?, Object?> raw) {
    final out = <String, Object?>{};
    raw.forEach((key, value) {
      out['$key'] = value;
    });
    return out;
  }

  Future<Map<String, Object?>> _buildManagedVaultCursorRemoteDiagnostics({
    required AppBackend backend,
    required SyncConfig? syncConfig,
    required CloudAuthScope? cloudScope,
  }) async {
    if (backend is! NativeAppBackend) return const <String, Object?>{};
    if (syncConfig?.backendType != SyncBackendType.managedVault) {
      return const <String, Object?>{};
    }

    final baseUrl = syncConfig?.baseUrl?.trim() ?? '';
    final vaultId = syncConfig?.remoteRoot.trim() ?? '';
    if (baseUrl.isEmpty || vaultId.isEmpty) {
      return const <String, Object?>{
        'managed_vault_cursor_remote_diagnostics': null,
        'managed_vault_cursor_remote_diagnostics_error':
            'missing_base_url_or_vault_id',
      };
    }

    final idToken = await readCloudCapabilityIdToken(
      cloudScope?.controller,
      mode: CloudCapabilityAuthMode.interactive,
    );

    final token = idToken?.trim();
    final appDir = (await getApplicationSupportDirectory()).path;
    final payload =
        await rust_sync_diagnostics.syncManagedVaultCursorDiagnostics(
      appDir: appDir,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: (token == null || token.isEmpty) ? null : token,
    );
    final decoded = jsonDecode(payload);

    if (decoded is Map<String, dynamic>) {
      return <String, Object?>{
        'managed_vault_cursor_remote_diagnostics':
            Map<String, Object?>.from(decoded),
      };
    }
    if (decoded is Map<Object?, Object?>) {
      return <String, Object?>{
        'managed_vault_cursor_remote_diagnostics': _toStringKeyMap(decoded),
      };
    }

    return const <String, Object?>{
      'managed_vault_cursor_remote_diagnostics': null,
      'managed_vault_cursor_remote_diagnostics_error':
          'invalid_managed_vault_cursor_payload',
    };
  }

  Future<String> _buildDiagnosticsJson() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final now = DateTime.now();

    final cloudScope = CloudAuthScope.maybeOf(context);
    final subscription = SubscriptionScope.maybeOf(context)?.status;
    final locale = Localizations.maybeLocaleOf(context);

    String? deviceId;
    try {
      deviceId = await backend.getOrCreateDeviceId();
    } catch (_) {
      deviceId = null;
    }

    String? activeEmbeddingModel;
    try {
      activeEmbeddingModel =
          await backend.getActiveEmbeddingModelName(sessionKey);
    } catch (_) {
      activeEmbeddingModel = null;
    }

    List<Map<String, Object?>> llmProfiles = const [];
    try {
      final profiles = await backend.listLlmProfiles(sessionKey);
      llmProfiles = profiles
          .map(
            (p) => <String, Object?>{
              'id': p.id,
              'name': p.name,
              'provider_type': p.providerType,
              'base_url': p.baseUrl,
              'model_name': p.modelName,
              'is_active': p.isActive,
              'created_at_ms': p.createdAtMs,
              'updated_at_ms': p.updatedAtMs,
            },
          )
          .toList(growable: false);
    } catch (_) {
      llmProfiles = const [];
    }

    SyncConfig? syncConfig;
    try {
      syncConfig = await SyncConfigStore().loadConfiguredSync();
    } catch (_) {
      syncConfig = null;
    }

    Map<String, Object?> syncDiagnostics;
    try {
      syncDiagnostics = await _buildSyncDiagnostics();
    } catch (_) {
      syncDiagnostics = const <String, Object?>{
        'last_sync_log': null,
        'sync_logs_by_backend': null,
        'sync_backoff_by_backend': null,
      };
    }

    Map<String, Object?> managedVaultCursorRemoteDiagnostics;
    try {
      managedVaultCursorRemoteDiagnostics =
          await _buildManagedVaultCursorRemoteDiagnostics(
        backend: backend,
        syncConfig: syncConfig,
        cloudScope: cloudScope,
      );
    } catch (e) {
      managedVaultCursorRemoteDiagnostics = <String, Object?>{
        'managed_vault_cursor_remote_diagnostics': null,
        'managed_vault_cursor_remote_diagnostics_error': '$e',
      };
    }

    List<Map<String, Object?>> updateLogs;
    try {
      final recent = await SharedPrefsUpdateEventLogger().readRecent();
      updateLogs =
          recent.map((entry) => entry.toJson()).toList(growable: false);
    } catch (_) {
      updateLogs = const <Map<String, Object?>>[];
    }

    final data = <String, Object?>{
      'generated_at_local': now.toIso8601String(),
      'generated_at_utc': now.toUtc().toIso8601String(),
      'platform': <String, Object?>{
        'k_is_web': kIsWeb,
        'debug': kDebugMode,
        'profile': kProfileMode,
        'release': kReleaseMode,
        'target_platform': defaultTargetPlatform.name,
      },
      'locale': <String, Object?>{
        'language_tag': locale?.toLanguageTag(),
      },
      'device_id': deviceId,
      'cloud': <String, Object?>{
        'uid': cloudScope?.controller.uid,
        'subscription_status': subscription?.name,
      },
      'sync': <String, Object?>{
        'backend': syncConfig?.backendType.name,
        'remote_root': syncConfig?.remoteRoot,
        'base_url': switch (syncConfig?.backendType) {
          SyncBackendType.webdav => syncConfig?.baseUrl,
          SyncBackendType.managedVault => syncConfig?.baseUrl,
          _ => null,
        },
        'local_dir': syncConfig?.backendType == SyncBackendType.localDir
            ? syncConfig?.localDir
            : null,
        ...syncDiagnostics,
        ...managedVaultCursorRemoteDiagnostics,
      },
      'embeddings': <String, Object?>{
        'active_model': activeEmbeddingModel,
      },
      'llm_profiles': llmProfiles,
      'update_logs': updateLogs,
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<String> _getJson() async {
    return _jsonFuture ??= _buildDiagnosticsJson();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    if (_busy) return;
    final t = context.t;
    setState(() => _busy = true);
    try {
      final json = await _getJson();
      await Clipboard.setData(ClipboardData(text: json));
      _showMessage(t.settings.diagnostics.messages.copied);
    } catch (e) {
      _showMessage(
        t.settings.diagnostics.messages.copyFailed(error: '$e'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareJson() async {
    if (_busy) return;
    final t = context.t;
    setState(() => _busy = true);
    try {
      final json = await _getJson();
      final safeTs =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(json)),
            mimeType: 'application/json',
            name: 'secondloop_diagnostics_$safeTs.json',
          ),
        ],
        text: '${t.app.title} ${t.settings.diagnostics.title}',
      );
    } catch (e) {
      _showMessage(
        t.settings.diagnostics.messages.shareFailed(error: '$e'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _jsonFuture ??= _buildDiagnosticsJson();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('diagnostics_page'),
      appBar: AppBar(
        title: Text(context.t.settings.diagnostics.title),
        actions: [
          IconButton(
            key: const ValueKey('diagnostics_copy'),
            tooltip: context.t.common.actions.copy,
            onPressed: _busy ? null : _copyToClipboard,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            key: const ValueKey('diagnostics_share'),
            tooltip: context.t.common.actions.share,
            onPressed: _busy ? null : _shareJson,
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _jsonFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Text(context.t.settings.diagnostics.loading),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                context.t.errors.loadFailed(error: '${snapshot.error}'),
              ),
            );
          }
          final json = snapshot.data ?? '{}';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(context.t.settings.diagnostics.privacyNote),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    json,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

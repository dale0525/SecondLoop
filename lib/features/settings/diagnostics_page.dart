import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../i18n/strings.g.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Future<String>? _jsonFuture;
  bool _busy = false;

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
        'gateway_base_url': cloudScope?.gatewayConfig.baseUrl,
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
      },
      'embeddings': <String, Object?>{
        'active_model': activeEmbeddingModel,
      },
      'llm_profiles': llmProfiles,
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<String> _getJson() async {
    return _jsonFuture ??= _buildDiagnosticsJson();
  }

  Future<void> _copyToClipboard() async {
    if (_busy) return;
    final t = context.t;
    setState(() => _busy = true);
    try {
      final json = await _getJson();
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.settings.diagnostics.messages.copied)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t.settings.diagnostics.messages.copyFailed(error: '$e'),
          ),
        ),
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
      final dir = await getTemporaryDirectory();
      final safeTs =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/secondloop_diagnostics_$safeTs.json');
      await file.writeAsString(json);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${t.app.title} ${t.settings.diagnostics.title}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t.settings.diagnostics.messages.shareFailed(error: '$e'),
          ),
        ),
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

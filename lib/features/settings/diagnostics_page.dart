import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/update/app_update_service.dart';
import '../../i18n/strings.g.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({
    super.key,
    this.updateService,
    this.externalUriLauncher,
  });

  final AppUpdateService? updateService;
  final Future<bool> Function(Uri uri)? externalUriLauncher;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Future<String>? _jsonFuture;
  bool _busy = false;
  bool _checkingUpdate = false;
  bool _updating = false;
  AppUpdateCheckResult? _updateResult;

  late final AppUpdateService _updateService;
  AppUpdateService? _ownedUpdateService;

  _DiagnosticsUpdateText get _updateText =>
      _DiagnosticsUpdateText.of(Localizations.localeOf(context));

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
      _showMessage(
        t.settings.diagnostics.messages.shareFailed(error: '$e'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkForUpdates({bool showMessage = true}) async {
    if (_checkingUpdate || _updating) return;

    setState(() => _checkingUpdate = true);
    final updatesT = _updateText;

    try {
      final result = await _updateService.checkForUpdates();
      if (!mounted) return;

      setState(() {
        _updateResult = result;
      });

      if (!showMessage) return;
      if (result.errorMessage != null) {
        _showMessage(
            updatesT.messages.checkFailed(error: result.errorMessage!));
      } else if (result.update == null) {
        _showMessage(updatesT.messages.upToDate);
      } else {
        _showMessage(
          updatesT.messages.updateAvailable(version: result.update!.latestTag),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(updatesT.messages.checkFailed(error: '$e'));
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _openUpdateExternally(Uri uri) async {
    final updatesT = _updateText;
    try {
      final launcher = widget.externalUriLauncher;
      final opened = launcher != null
          ? await launcher(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        _showMessage(updatesT.messages.openFailed);
      }
    } catch (_) {
      _showMessage(updatesT.messages.openFailed);
    }
  }

  Future<void> _applyUpdate() async {
    if (_checkingUpdate || _updating) return;
    final update = _updateResult?.update;
    if (update == null) return;

    if (!update.canSeamlessInstall) {
      await _openUpdateExternally(update.downloadUri);
      return;
    }

    final updatesT = _updateText;
    setState(() => _updating = true);
    try {
      _showMessage(updatesT.messages.installStarting);
      await _updateService.installAndRestart(update);
    } catch (e) {
      _showMessage(updatesT.messages.installFailed(error: '$e'));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  String _updateStatusText() {
    final updatesT = _updateText;
    if (_checkingUpdate) return updatesT.status.checking;
    final result = _updateResult;
    if (result == null) return updatesT.status.idle;
    if (result.errorMessage != null) {
      return updatesT.status.failed(error: result.errorMessage!);
    }
    final update = result.update;
    if (update == null) return updatesT.status.upToDate;
    if (update.canSeamlessInstall) {
      return updatesT.status.availableSeamless(version: update.latestTag);
    }
    return updatesT.status.availableExternal(version: update.latestTag);
  }

  Widget _buildUpdateCard() {
    final updatesT = _updateText;
    final update = _updateResult?.update;
    final latestVersionText = update == null
        ? null
        : updatesT.latestVersion(version: update.latestTag);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              updatesT.title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(_updateStatusText()),
            const SizedBox(height: 4),
            Text(
              updatesT.currentVersion(
                version:
                    _updateResult?.currentVersion ?? updatesT.unknownVersion,
              ),
            ),
            if (latestVersionText != null) ...[
              const SizedBox(height: 4),
              Text(latestVersionText),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('diagnostics_check_updates'),
                  onPressed:
                      (_checkingUpdate || _updating) ? null : _checkForUpdates,
                  icon: _checkingUpdate
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_alt_rounded),
                  label: Text(
                    _checkingUpdate
                        ? updatesT.actions.checking
                        : updatesT.actions.check,
                  ),
                ),
                if (update != null)
                  FilledButton.icon(
                    key: const ValueKey('diagnostics_apply_update'),
                    onPressed:
                        (_checkingUpdate || _updating) ? null : _applyUpdate,
                    icon: _updating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            update.canSeamlessInstall
                                ? Icons.restart_alt_rounded
                                : Icons.open_in_new_rounded,
                          ),
                    label: Text(
                      _updating
                          ? updatesT.actions.updating
                          : update.canSeamlessInstall
                              ? updatesT.actions.updateAndRestart
                              : updatesT.actions.openDownload,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final provided = widget.updateService;
    if (provided != null) {
      _updateService = provided;
    } else {
      final owned = AppUpdateService();
      _updateService = owned;
      _ownedUpdateService = owned;
    }
  }

  @override
  void dispose() {
    _ownedUpdateService?.dispose();
    super.dispose();
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
              _buildUpdateCard(),
              const SizedBox(height: 12),
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

class _DiagnosticsUpdateText {
  const _DiagnosticsUpdateText._(this._isZh);

  final bool _isZh;

  static _DiagnosticsUpdateText of(Locale locale) {
    final languageCode = locale.languageCode.toLowerCase();
    return _DiagnosticsUpdateText._(languageCode.startsWith('zh'));
  }

  String get title => _isZh ? '应用更新' : 'App updates';
  String get unknownVersion => _isZh ? '未知' : 'unknown';

  String currentVersion({required String version}) =>
      _isZh ? '当前版本：$version' : 'Current version: $version';

  String latestVersion({required String version}) =>
      _isZh ? '最新版本：$version' : 'Latest version: $version';

  _DiagnosticsUpdateStatusText get status =>
      _DiagnosticsUpdateStatusText(_isZh);
  _DiagnosticsUpdateActionText get actions =>
      _DiagnosticsUpdateActionText(_isZh);
  _DiagnosticsUpdateMessageText get messages =>
      _DiagnosticsUpdateMessageText(_isZh);
}

class _DiagnosticsUpdateStatusText {
  const _DiagnosticsUpdateStatusText(this._isZh);

  final bool _isZh;

  String get idle => _isZh
      ? '点击检查更新；Linux 可自动更新重启，Windows 请下载 MSI 安装。'
      : 'Check for updates. Linux can auto-update and restart; Windows uses MSI download/install.';

  String get checking => _isZh ? '正在检查更新…' : 'Checking for updates…';

  String get upToDate => _isZh ? '当前已是最新版本。' : 'You\'re on the latest version.';

  String availableSeamless({required String version}) => _isZh
      ? '发现新版本（$version）。点击更新后将自动重启并完成安装。'
      : 'Update available ($version). Click update to restart and apply automatically.';

  String availableExternal({required String version}) => _isZh
      ? '发现新版本（$version）。请打开下载页完成安装（Windows 为 MSI）。'
      : 'Update available ($version). Open the download page to install (MSI on Windows).';

  String failed({required String error}) =>
      _isZh ? '检查更新失败：$error' : 'Update check failed: $error';
}

class _DiagnosticsUpdateActionText {
  const _DiagnosticsUpdateActionText(this._isZh);

  final bool _isZh;

  String get check => _isZh ? '检查更新' : 'Check updates';
  String get checking => _isZh ? '检查中…' : 'Checking…';
  String get updateAndRestart => _isZh ? '更新并重启' : 'Update and restart';
  String get openDownload => _isZh ? '打开下载页面' : 'Open download page';
  String get updating => _isZh ? '更新中…' : 'Updating…';
}

class _DiagnosticsUpdateMessageText {
  const _DiagnosticsUpdateMessageText(this._isZh);

  final bool _isZh;

  String get upToDate =>
      _isZh ? '当前已是最新版本' : 'You\'re already on the latest version';

  String updateAvailable({required String version}) =>
      _isZh ? '发现新版本：$version' : 'Update available: $version';

  String checkFailed({required String error}) =>
      _isZh ? '检查更新失败：$error' : 'Failed to check updates: $error';

  String get installStarting => _isZh
      ? '正在准备更新，应用即将重启。'
      : 'Preparing update. The app will restart shortly.';

  String installFailed({required String error}) =>
      _isZh ? '更新失败：$error' : 'Update failed: $error';

  String get openFailed =>
      _isZh ? '无法打开下载页面' : 'Could not open the download page';
}

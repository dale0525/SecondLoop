import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/app_update_service.dart';

typedef AboutRuntimeVersionLoader = Future<AppRuntimeVersion> Function();
typedef AboutExternalUriLauncher = Future<bool> Function(Uri uri);

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    this.updateService,
    this.runtimeVersionLoader,
    this.externalUriLauncher,
  });

  static final Uri homepageUri = Uri.parse('https://secondloop.app');
  static final Uri releasePageUri =
      Uri.parse('https://github.com/dale0525/SecondLoop/releases/latest');

  final AppUpdateService? updateService;
  final AboutRuntimeVersionLoader? runtimeVersionLoader;
  final AboutExternalUriLauncher? externalUriLauncher;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _checkingUpdate = false;
  bool _updating = false;

  AppRuntimeVersion? _runtimeVersion;
  AppUpdateCheckResult? _updateResult;

  late final AppUpdateService _updateService;
  AppUpdateService? _ownedUpdateService;

  _AboutText get _text => _AboutText.of(Localizations.localeOf(context));

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

    unawaited(_loadRuntimeVersion());
  }

  @override
  void dispose() {
    _ownedUpdateService?.dispose();
    super.dispose();
  }

  Future<void> _loadRuntimeVersion() async {
    final loader = widget.runtimeVersionLoader;
    AppRuntimeVersion runtimeVersion;
    if (loader != null) {
      runtimeVersion = await loader();
    } else {
      try {
        final info = await PackageInfo.fromPlatform();
        runtimeVersion = AppRuntimeVersion(
          version: info.version,
          buildNumber: info.buildNumber,
        );
      } catch (_) {
        runtimeVersion =
            const AppRuntimeVersion(version: '0.0.0', buildNumber: '0');
      }
    }

    if (!mounted) return;
    setState(() {
      _runtimeVersion = runtimeVersion;
    });
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

  Future<void> _openExternalUri(
    Uri uri, {
    required String failedMessage,
  }) async {
    try {
      final launcher = widget.externalUriLauncher;
      final opened = launcher != null
          ? await launcher(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        _showMessage(failedMessage);
      }
    } catch (_) {
      _showMessage(failedMessage);
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate || _updating) return;
    setState(() => _checkingUpdate = true);

    try {
      final result = await _updateService.checkForUpdates();
      if (!mounted) return;
      setState(() {
        _updateResult = result;
      });

      if (result.errorMessage != null) {
        _showMessage(_text.messages.checkFailed(error: result.errorMessage!));
      } else if (result.update == null) {
        _showMessage(_text.messages.upToDate);
      } else {
        _showMessage(
          _text.messages.updateAvailable(version: result.update!.latestTag),
        );
      }
    } catch (error) {
      _showMessage(_text.messages.checkFailed(error: '$error'));
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _autoUpdateAndRestart() async {
    if (_checkingUpdate || _updating) return;
    final update = _updateResult?.update;
    if (update == null || !update.canSeamlessInstall) return;

    setState(() => _updating = true);
    try {
      _showMessage(_text.messages.installStarting);
      await _updateService.installAndRestart(update);
    } catch (error) {
      _showMessage(_text.messages.installFailed(error: '$error'));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _manualUpdate() {
    final uri = _updateResult?.update?.downloadUri ?? AboutPage.releasePageUri;
    return _openExternalUri(
      uri,
      failedMessage: _text.messages.openUpdateFailed,
    );
  }

  String _currentVersionText() {
    if (_updateResult?.currentVersion != null) {
      return _updateResult!.currentVersion;
    }
    return _runtimeVersion?.display ?? _text.unknownVersion;
  }

  String _updateStatusText() {
    if (_checkingUpdate) return _text.status.checking;

    final result = _updateResult;
    if (result == null) {
      return _text.status.idle;
    }
    if (result.errorMessage != null) {
      return _text.status.failed(error: result.errorMessage!);
    }

    final update = result.update;
    if (update == null) {
      return _text.status.upToDate;
    }
    if (update.canSeamlessInstall) {
      return _text.status.availableSeamless(version: update.latestTag);
    }
    return _text.status.availableExternal(version: update.latestTag);
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final update = _updateResult?.update;

    return Scaffold(
      key: const ValueKey('about_page'),
      appBar: AppBar(
        title: Text(text.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DecoratedBox(
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
                    text.productName,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(text.currentVersion(version: _currentVersionText())),
                  if (update != null) ...[
                    const SizedBox(height: 4),
                    Text(text.latestVersion(version: update.latestTag)),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('about_open_homepage'),
                    onPressed: () => _openExternalUri(
                      AboutPage.homepageUri,
                      failedMessage: text.messages.openHomepageFailed,
                    ),
                    icon: const Icon(Icons.public_rounded),
                    label: Text(text.openHomepage),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
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
                    text.updatesTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(_updateStatusText()),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('about_check_updates'),
                        onPressed: (_checkingUpdate || _updating)
                            ? null
                            : _checkForUpdates,
                        icon: _checkingUpdate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.system_update_alt_rounded),
                        label: Text(
                          _checkingUpdate
                              ? text.actions.checking
                              : text.actions.check,
                        ),
                      ),
                      if (update != null && update.canSeamlessInstall)
                        FilledButton.icon(
                          key: const ValueKey('about_auto_update'),
                          onPressed: (_checkingUpdate || _updating)
                              ? null
                              : _autoUpdateAndRestart,
                          icon: _updating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.restart_alt_rounded),
                          label: Text(
                            _updating
                                ? text.actions.updating
                                : text.actions.autoUpdate,
                          ),
                        ),
                      TextButton.icon(
                        key: const ValueKey('about_manual_update'),
                        onPressed: (_checkingUpdate || _updating)
                            ? null
                            : _manualUpdate,
                        icon: const Icon(Icons.download_rounded),
                        label: Text(text.actions.manualUpdate),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutText {
  const _AboutText._(this._isZh);

  final bool _isZh;

  static _AboutText of(Locale locale) {
    final languageCode = locale.languageCode.toLowerCase();
    return _AboutText._(languageCode.startsWith('zh'));
  }

  String get title => _isZh ? '关于' : 'About';
  String get productName => _isZh ? 'SecondLoop' : 'SecondLoop';
  String get updatesTitle => _isZh ? '应用更新' : 'App updates';
  String get openHomepage => _isZh ? '项目主页' : 'Project homepage';
  String get unknownVersion => _isZh ? '未知' : 'unknown';

  String currentVersion({required String version}) =>
      _isZh ? '当前版本：$version' : 'Current version: $version';

  String latestVersion({required String version}) =>
      _isZh ? '最新版本：$version' : 'Latest version: $version';

  _AboutStatusText get status => _AboutStatusText(_isZh);
  _AboutActionText get actions => _AboutActionText(_isZh);
  _AboutMessageText get messages => _AboutMessageText(_isZh);
}

class _AboutStatusText {
  const _AboutStatusText(this._isZh);

  final bool _isZh;

  String get idle => _isZh
      ? '点击检查更新；Linux 可自动更新重启，Windows 请下载 MSI 安装。'
      : 'Check for updates. Linux can auto-update and restart; Windows uses MSI download/install.';

  String get checking => _isZh ? '正在检查更新…' : 'Checking for updates…';

  String get upToDate => _isZh ? '当前已是最新版本。' : 'You\'re on the latest version.';

  String availableSeamless({required String version}) => _isZh
      ? '发现新版本（$version）。可一键自动更新并重启。'
      : 'Update available ($version). You can auto-update and restart.';

  String availableExternal({required String version}) => _isZh
      ? '发现新版本（$version）。请手动下载安装。'
      : 'Update available ($version). Please download and install manually.';

  String failed({required String error}) =>
      _isZh ? '检查更新失败：$error' : 'Update check failed: $error';
}

class _AboutActionText {
  const _AboutActionText(this._isZh);

  final bool _isZh;

  String get check => _isZh ? '检查更新' : 'Check updates';
  String get checking => _isZh ? '检查中…' : 'Checking…';
  String get autoUpdate => _isZh ? '自动更新并重启' : 'Auto-update and restart';
  String get manualUpdate => _isZh ? '手动更新' : 'Manual update';
  String get updating => _isZh ? '更新中…' : 'Updating…';
}

class _AboutMessageText {
  const _AboutMessageText(this._isZh);

  final bool _isZh;

  String get upToDate =>
      _isZh ? '当前已是最新版本' : 'You\'re already on the latest version';

  String updateAvailable({required String version}) =>
      _isZh ? '发现新版本：$version' : 'Update available: $version';

  String checkFailed({required String error}) =>
      _isZh ? '检查更新失败：$error' : 'Failed to check updates: $error';

  String get installStarting => _isZh
      ? '正在准备自动更新，应用即将重启。'
      : 'Preparing update. The app will restart shortly.';

  String installFailed({required String error}) =>
      _isZh ? '自动更新失败：$error' : 'Auto update failed: $error';

  String get openHomepageFailed =>
      _isZh ? '无法打开项目主页' : 'Could not open project homepage';

  String get openUpdateFailed =>
      _isZh ? '无法打开更新页面' : 'Could not open update page';
}

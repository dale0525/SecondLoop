import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/android/android_apk_installer.dart';
import '../../core/update/android/android_apk_update_coordinator.dart';
import '../../core/update/app_update_flow.dart';
import '../../core/update/app_update_service.dart';
import '../../core/update/update_badge_prefs.dart';
import '../../i18n/strings.g.dart';

typedef AboutRuntimeVersionLoader = Future<AppRuntimeVersion> Function();
typedef AboutExternalUriLauncher = Future<bool> Function(Uri uri);

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    this.updateService,
    this.runtimeVersionLoader,
    this.externalUriLauncher,
    this.androidApkDownloader,
    this.androidApkInstaller,
    this.enableAndroidApkInstallInDebug = false,
  });

  static final Uri homepageUri = Uri.parse('https://secondloop.app');
  static final Uri releasePageUri =
      Uri.parse('https://github.com/dale0525/SecondLoop/releases/latest');

  final AppUpdateService? updateService;
  final AboutRuntimeVersionLoader? runtimeVersionLoader;
  final AboutExternalUriLauncher? externalUriLauncher;
  final AndroidApkDownloader? androidApkDownloader;
  final AndroidApkInstaller? androidApkInstaller;
  final bool enableAndroidApkInstallInDebug;

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
  late final AndroidApkDownloader _androidApkDownloader;
  AndroidApkDownloader? _ownedAndroidApkDownloader;
  late final AndroidApkInstaller _androidApkInstaller;
  late final AndroidApkUpdateCoordinator _androidApkUpdateCoordinator;

  _AboutText get _text => _AboutText.of(context);
  bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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

    final providedDownloader = widget.androidApkDownloader;
    if (providedDownloader != null) {
      _androidApkDownloader = providedDownloader;
    } else {
      final owned = HttpAndroidApkDownloader();
      _androidApkDownloader = owned;
      _ownedAndroidApkDownloader = owned;
    }
    _androidApkInstaller =
        widget.androidApkInstaller ?? MethodChannelAndroidApkInstaller();
    _androidApkUpdateCoordinator = AndroidApkUpdateCoordinator(
      downloader: _androidApkDownloader,
      installer: _androidApkInstaller,
    );

    unawaited(_loadRuntimeVersion());
  }

  @override
  void dispose() {
    _ownedUpdateService?.dispose();
    final ownedDownloader = _ownedAndroidApkDownloader;
    if (ownedDownloader is HttpAndroidApkDownloader) {
      unawaited(ownedDownloader.dispose());
    }
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
    setState(() {
      _checkingUpdate = true;
    });

    try {
      final result = await _updateService.checkForUpdates();
      if (!mounted) return;
      setState(() {
        _updateResult = result;
      });

      if (result.errorMessage != null) {
        _showMessage(_text.messages.checkFailed(error: result.errorMessage!));
      } else if (result.update == null) {
        await UpdateBadgePrefs.clear();
        _showMessage(_text.messages.upToDate);
      } else {
        await UpdateBadgePrefs.setAvailableVersion(result.update!.latestTag);
        _showMessage(
          _text.messages.updateAvailable(version: result.update!.latestTag),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _updateResult = null;
        });
      }
      _showMessage(_text.messages.checkFailed(error: '$error'));
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  bool _canUseAndroidApkUpdate(AppUpdateAvailability update) {
    final allowAndroidApkInstall =
        kReleaseMode || widget.enableAndroidApkInstallInDebug;
    return _isAndroidPlatform &&
        allowAndroidApkInstall &&
        update.canUseAndroidApkInstaller;
  }

  bool _isAndroidApkRelease(AppUpdateAvailability update) {
    return _isAndroidPlatform &&
        update.asset != null &&
        isAndroidApkAssetForUpdate(update.asset!);
  }

  bool _shouldOpenAndroidApkExternally(AppUpdateAvailability update) {
    return _isAndroidApkRelease(update) && !_canUseAndroidApkUpdate(update);
  }

  Future<void> _applyManagedUpdate() async {
    if (_checkingUpdate || _updating) return;
    final update = _updateResult?.update;
    if (update == null) return;

    final useAndroidApkUpdate = _canUseAndroidApkUpdate(update);
    final openAndroidApkExternally = _shouldOpenAndroidApkExternally(update);
    setState(() {
      _updating = true;
    });
    try {
      if (openAndroidApkExternally) {
        await _openExternalUri(
          update.releasePageUri,
          failedMessage: _text.messages.openUpdateFailed,
        );
        return;
      }
      await showAppUpdateProgressDialog(
        context: context,
        update: update,
        updateService: _updateService,
        androidApkUpdateCoordinator:
            useAndroidApkUpdate ? _androidApkUpdateCoordinator : null,
        externalUriLauncher: widget.externalUriLauncher,
        useAndroidApkUpdate: useAndroidApkUpdate,
      );
    } catch (error) {
      _showMessage(_text.messages.installFailed(error: '$error'));
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
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
    if (_isAndroidApkRelease(update) && !_canUseAndroidApkUpdate(update)) {
      return _text.status.availableExternal(version: update.latestTag);
    }
    if (_canUseAndroidApkUpdate(update)) {
      return _text.status.availableAndroidApk(version: update.latestTag);
    }
    if (update.canSeamlessInstall) {
      return _text.status.availableSeamless(version: update.latestTag);
    }
    if (update.canStageForNextLaunch) {
      return _text.status.availableStaged(version: update.latestTag);
    }
    return _text.status.availableExternal(version: update.latestTag);
  }

  IconData _updateActionIcon(AppUpdateAvailability? update) {
    if (update == null) {
      return Icons.system_update_alt_rounded;
    }
    if (_shouldOpenAndroidApkExternally(update)) {
      return Icons.open_in_new_rounded;
    }
    if (_canUseAndroidApkUpdate(update)) {
      return Icons.download_rounded;
    }
    if (!update.canSeamlessInstall && !update.canStageForNextLaunch) {
      return Icons.open_in_new_rounded;
    }
    return Icons.restart_alt_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final update = _updateResult?.update;
    final updateActionLabel = update == null
        ? (_checkingUpdate ? text.actions.checking : text.actions.check)
        : (_updating ? text.actions.updating : text.actions.autoUpdate);

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
                            : (update == null
                                ? _checkForUpdates
                                : _applyManagedUpdate),
                        icon: _checkingUpdate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_updateActionIcon(update)),
                        label: Text(updateActionLabel),
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
  const _AboutText._(this._t);

  final Translations _t;

  static _AboutText of(BuildContext context) {
    return _AboutText._(context.t);
  }

  String get title => _t.settings.about.title;
  String get productName => _t.settings.about.productName;
  String get updatesTitle => _t.settings.about.updatesTitle;
  String get openHomepage => _t.settings.about.openHomepage;
  String get unknownVersion => _t.settings.about.unknownVersion;
  String currentVersion({required Object version}) =>
      _t.settings.about.currentVersion(version: version);
  String latestVersion({required Object version}) =>
      _t.settings.about.latestVersion(version: version);
  _AboutStatusText get status => _AboutStatusText(_t);
  _AboutActionText get actions => _AboutActionText(_t);
  _AboutMessageText get messages => _AboutMessageText(_t);
}

class _AboutStatusText {
  const _AboutStatusText(this._t);

  final Translations _t;

  String get idle => _t.settings.about.status.idle;
  String get checking => _t.settings.about.status.checking;
  String get upToDate => _t.settings.about.status.upToDate;
  String availableSeamless({required Object version}) =>
      _t.settings.about.status.availableSeamless(version: version);
  String availableAndroidApk({required Object version}) =>
      _t.settings.about.status.availableAndroidApk(version: version);
  String availableStaged({required Object version}) =>
      _t.settings.about.status.availableStaged(version: version);
  String availableExternal({required Object version}) =>
      _t.settings.about.status.availableExternal(version: version);
  String failed({required Object error}) =>
      _t.settings.about.status.failed(error: error);
}

class _AboutActionText {
  const _AboutActionText(this._t);

  final Translations _t;

  String get check => _t.settings.about.actions.check;
  String get checking => _t.settings.about.actions.checking;
  String get autoUpdate => _t.settings.about.actions.autoUpdate;
  String get updating => _t.settings.about.actions.updating;
}

class _AboutMessageText {
  const _AboutMessageText(this._t);

  final Translations _t;

  String get upToDate => _t.settings.about.messages.upToDate;
  String updateAvailable({required Object version}) =>
      _t.settings.about.messages.updateAvailable(version: version);
  String checkFailed({required Object error}) =>
      _t.settings.about.messages.checkFailed(error: error);
  String get installStarting => _t.settings.about.messages.installStarting;
  String get stageStarting => _t.settings.about.messages.stageStarting;
  String get stageReady => _t.settings.about.messages.stageReady;
  String installFailed({required Object error}) =>
      _t.settings.about.messages.installFailed(error: error);
  String stageFailed({required Object error}) =>
      _t.settings.about.messages.stageFailed(error: error);
  String get openHomepageFailed =>
      _t.settings.about.messages.openHomepageFailed;
  String get openUpdateFailed => _t.settings.about.messages.openUpdateFailed;
}

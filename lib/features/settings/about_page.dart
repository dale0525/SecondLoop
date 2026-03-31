import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/android/android_apk_installer.dart';
import '../../core/update/android/android_apk_update_coordinator.dart';
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
  });

  static final Uri homepageUri = Uri.parse('https://secondloop.app');
  static final Uri releasePageUri =
      Uri.parse('https://github.com/dale0525/SecondLoop/releases/latest');

  final AppUpdateService? updateService;
  final AboutRuntimeVersionLoader? runtimeVersionLoader;
  final AboutExternalUriLauncher? externalUriLauncher;
  final AndroidApkDownloader? androidApkDownloader;
  final AndroidApkInstaller? androidApkInstaller;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _checkingUpdate = false;
  bool _updating = false;
  bool _androidUpdateCancelling = false;
  AndroidApkDownloadProgress? _androidDownloadProgress;
  String? _androidUpdateError;
  AndroidApkDownloadCancelToken? _androidDownloadCancelToken;

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
    _androidDownloadCancelToken?.cancel();
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
    final asset = update.asset;
    return _isAndroidPlatform &&
        update.installMode == AppUpdateInstallMode.externalDownload &&
        asset != null &&
        asset.name.toLowerCase().endsWith('.apk');
  }

  Future<void> _applyManagedUpdate() async {
    if (_checkingUpdate || _updating) return;
    final update = _updateResult?.update;
    if (update == null) return;

    final useAndroidApkUpdate = _canUseAndroidApkUpdate(update);
    final cancelToken =
        useAndroidApkUpdate ? AndroidApkDownloadCancelToken() : null;

    setState(() {
      _updating = true;
      _androidUpdateCancelling = false;
      _androidDownloadProgress = null;
      _androidUpdateError = null;
      _androidDownloadCancelToken = cancelToken;
    });
    var stagedFlow = false;
    try {
      if (useAndroidApkUpdate) {
        _showMessage(_text.messages.installStarting);
        await _androidApkUpdateCoordinator.performUpdate(
          asset: update.asset!,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _androidDownloadProgress = progress;
            });
          },
          cancelToken: cancelToken,
        );
      } else if (update.canSeamlessInstall) {
        _showMessage(_text.messages.installStarting);
        await _updateService.installAndRestart(update);
      } else if (update.canStageForNextLaunch) {
        stagedFlow = true;
        _showMessage(_text.messages.stageStarting);
        await _updateService.stageUpdateForNextLaunch(update);
        _showMessage(_text.messages.stageReady);
      }
    } catch (error) {
      if (error is AndroidApkDownloadCancelledException) {
      } else if (stagedFlow) {
        _showMessage(_text.messages.stageFailed(error: '$error'));
      } else {
        if (_isAndroidPlatform && _canUseAndroidApkUpdate(update)) {
          if (mounted) {
            setState(() {
              _androidUpdateError = _androidUpdateErrorText(error);
            });
          }
        }
        _showMessage(_text.messages.installFailed(error: '$error'));
      }
    } finally {
      _androidDownloadCancelToken = null;
      if (mounted) {
        setState(() {
          _updating = false;
          _androidUpdateCancelling = false;
        });
      }
    }
  }

  void _cancelAndroidUpdate() {
    _androidDownloadCancelToken?.cancel();
    if (!mounted) return;
    setState(() {
      _androidUpdateCancelling = true;
      _androidDownloadProgress = null;
      _androidUpdateError = null;
    });
  }

  String _androidUpdateErrorText(Object error) {
    final dialogText = context.t.settings.updateDialog;
    if (error is AndroidApkUpdateException) {
      switch (error.type) {
        case AndroidApkUpdateFailureType.download:
        case AndroidApkUpdateFailureType.integrityCheck:
          return dialogText.downloadFailed;
        case AndroidApkUpdateFailureType.installLaunch:
          return context.t.settings.about.messages.openUpdateFailed;
      }
    }
    return dialogText.downloadFailed;
  }

  Future<void> _manualUpdate() {
    final update = _updateResult?.update;
    final uri = update == null
        ? AboutPage.releasePageUri
        : (_canUseAndroidApkUpdate(update)
            ? update.downloadUri
            : update.releasePageUri);
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
    if (_canUseAndroidApkUpdate(update) || update.canSeamlessInstall) {
      return _text.status.availableSeamless(version: update.latestTag);
    }
    if (update.canStageForNextLaunch) {
      return _text.status.availableStaged(version: update.latestTag);
    }
    return _text.status.availableExternal(version: update.latestTag);
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final update = _updateResult?.update;
    final showManagedAction = update != null &&
        (update.canSeamlessInstall ||
            update.canStageForNextLaunch ||
            _canUseAndroidApkUpdate(update));
    final androidProgress = _androidDownloadProgress;
    final androidUpdateError = _androidUpdateError;

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
                  if (_updating &&
                      _isAndroidPlatform &&
                      androidProgress != null) ...[
                    LinearProgressIndicator(
                      key: const ValueKey('about_android_progress_bar'),
                      value: androidProgress.fraction,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      androidProgress.percent == null
                          ? context
                              .t.settings.updateDialog.downloadProgressUnknown
                          : context.t.settings.updateDialog.downloadProgress(
                              percent: androidProgress.percent!,
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('about_check_updates'),
                        onPressed: (_checkingUpdate ||
                                _updating ||
                                _androidUpdateCancelling)
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
                      if (showManagedAction)
                        FilledButton.icon(
                          key: const ValueKey('about_auto_update'),
                          onPressed: (_checkingUpdate || _updating)
                              ? null
                              : (_androidUpdateCancelling
                                  ? null
                                  : _applyManagedUpdate),
                          icon: _updating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  update.canStageForNextLaunch
                                      ? Icons.download_done_rounded
                                      : Icons.restart_alt_rounded,
                                ),
                          label: Text(
                            _updating
                                ? text.actions.updating
                                : update.canStageForNextLaunch
                                    ? text.actions.stageUpdate
                                    : text.actions.autoUpdate,
                          ),
                        ),
                      if (_updating && _isAndroidPlatform)
                        OutlinedButton.icon(
                          key: const ValueKey('about_android_cancel'),
                          onPressed: _cancelAndroidUpdate,
                          icon: const Icon(Icons.close_rounded),
                          label: Text(context.t.common.actions.cancel),
                        ),
                      if (!_updating &&
                          _isAndroidPlatform &&
                          androidUpdateError != null)
                        OutlinedButton.icon(
                          key: const ValueKey('about_android_retry'),
                          onPressed: _applyManagedUpdate,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(context.t.common.actions.retry),
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
  String get stageUpdate => _t.settings.about.actions.stageUpdate;
  String get manualUpdate => _t.settings.about.actions.manualUpdate;
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

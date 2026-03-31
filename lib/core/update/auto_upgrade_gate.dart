import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/strings.g.dart';
import 'android/android_apk_installer.dart';
import 'android/android_apk_update_coordinator.dart';
import 'app_update_service.dart';
import 'release_notes_service.dart';
import 'update_badge_prefs.dart';

typedef AutoUpgradeGateExternalUriLauncher = Future<bool> Function(Uri uri);

class AutoUpgradeGate extends StatefulWidget {
  const AutoUpgradeGate({
    super.key,
    required this.child,
    this.updateService,
    this.releaseNotesService,
    this.enableInDebug = false,
    this.externalUriLauncher,
    this.androidApkDownloader,
    this.androidApkInstaller,
  });

  final Widget child;
  final AppUpdateService? updateService;
  final ReleaseNotesService? releaseNotesService;
  final bool enableInDebug;
  final AutoUpgradeGateExternalUriLauncher? externalUriLauncher;
  final AndroidApkDownloader? androidApkDownloader;
  final AndroidApkInstaller? androidApkInstaller;

  static const updateNoticeLastTagPrefsKey = 'update_notice_last_tag_v1';
  static const updateNoticeLastShownAtMsPrefsKey =
      'update_notice_last_shown_at_ms_v1';
  static const updateNoticeDismissedInSessionPrefsKey =
      'update_notice_dismissed_in_session_v1';
  static const updateReadyAckTagPrefsKey = 'update_ready_ack_tag_v1';
  static Uri fallbackUpdateUri({required String releaseRepo}) {
    final normalizedRepo =
        releaseRepo.trim().isEmpty ? 'dale0525/SecondLoop' : releaseRepo.trim();
    return Uri.parse('https://github.com/$normalizedRepo/releases/latest');
  }

  @override
  State<AutoUpgradeGate> createState() => _AutoUpgradeGateState();
}

class _AutoUpgradeGateState extends State<AutoUpgradeGate>
    with WidgetsBindingObserver {
  static const _updateNoticeCooldown = Duration(hours: 24);

  bool _checkScheduled = false;
  bool _noticeSessionInitialized = false;
  bool _updateNoticeDismissedInSession = false;
  bool _androidDialogOpen = false;
  bool _androidCheckInFlight = false;
  String? _dismissedAndroidUpdateTagInSession;

  late final AppUpdateService _updateService;
  AppUpdateService? _ownedUpdateService;
  late final ReleaseNotesService _releaseNotesService;
  ReleaseNotesService? _ownedReleaseNotesService;
  AndroidApkDownloader? _ownedAndroidApkDownloader;
  late final AndroidApkDownloader _androidApkDownloader;
  late final AndroidApkInstaller _androidApkInstaller;

  bool get _isWindowsPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool get _isMacosPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  bool get _isLinuxPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _usesPassiveManagedUpdates =>
      _isWindowsPlatform || _isMacosPlatform || _isLinuxPlatform;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final provided = widget.updateService;
    if (provided != null) {
      _updateService = provided;
    } else {
      final owned = AppUpdateService();
      _updateService = owned;
      _ownedUpdateService = owned;
    }

    final providedReleaseNotes = widget.releaseNotesService;
    if (providedReleaseNotes != null) {
      _releaseNotesService = providedReleaseNotes;
    } else {
      final owned = ReleaseNotesService();
      _releaseNotesService = owned;
      _ownedReleaseNotesService = owned;
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeAutoUpgrade());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAndroidPlatform) return;
    if (state != AppLifecycleState.resumed) return;
    unawaited(_maybeAutoUpgrade());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ownedUpdateService?.dispose();
    _ownedReleaseNotesService?.dispose();
    final ownedDownloader = _ownedAndroidApkDownloader;
    if (ownedDownloader is HttpAndroidApkDownloader) {
      unawaited(ownedDownloader.dispose());
    }
    super.dispose();
  }

  Future<void> _maybeAutoUpgrade() async {
    if (!kReleaseMode && !widget.enableInDebug) return;
    if (_androidCheckInFlight) return;
    _androidCheckInFlight = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await _initializeNoticeSession(prefs);

      Object? pendingApplyError;
      var startupApplySucceeded = false;
      try {
        startupApplySucceeded =
            await _updateService.applyPendingUpdateOnStartup();
      } catch (error, stackTrace) {
        pendingApplyError = error;
        debugPrint('auto_upgrade_pending_apply_skipped: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      if (startupApplySucceeded) {
        await UpdateBadgePrefs.clear();
        return;
      }

      try {
        final result = await _updateService.checkForUpdates();
        final update = result.update;
        if (update == null) {
          await UpdateBadgePrefs.clear();
          if (pendingApplyError != null) {
            await _showPendingApplyFailureNotice(pendingApplyError);
          }
          return;
        }

        await UpdateBadgePrefs.setAvailableVersion(update.latestTag);
        if (pendingApplyError != null) {
          await _showPendingApplyFailureNotice(pendingApplyError);
          return;
        }

        if (_isAndroidPlatform && _isAndroidUpdateCandidate(update)) {
          if (_dismissedAndroidUpdateTagInSession == update.latestTag) {
            return;
          }
          await _showAndroidUpdateDialog(update);
          return;
        }

        if (_usesPassiveManagedUpdates) {
          var stagedReady = false;
          if (_isWindowsPlatform && update.canSeamlessInstall) {
            try {
              await _updateService.stageUpdateForNextLaunch(update);
              stagedReady = true;
            } catch (error, stackTrace) {
              debugPrint('auto_upgrade_stage_skipped: $error');
              debugPrintStack(stackTrace: stackTrace);
            }
          }
          await _maybeShowPassiveUpdateNotice(
            prefs: prefs,
            update: update,
            stagedReady: stagedReady,
          );
          return;
        }

        if (update.canSeamlessInstall) {
          await _updateService.installAndRestart(update);
          return;
        }

        var stagedReady = false;
        if (update.canStageForNextLaunch) {
          await _updateService.stageUpdateForNextLaunch(update);
          stagedReady = true;
        }

        await _maybeShowPassiveUpdateNotice(
          prefs: prefs,
          update: update,
          stagedReady: stagedReady,
        );
      } catch (error, stackTrace) {
        debugPrint('auto_upgrade_skipped: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (pendingApplyError != null) {
          await _showPendingApplyFailureNotice(pendingApplyError);
        }
      }
    } finally {
      _androidCheckInFlight = false;
    }
  }

  bool _isAndroidUpdateCandidate(AppUpdateAvailability update) {
    final asset = update.asset;
    return asset != null && asset.name.toLowerCase().endsWith('.apk');
  }

  Future<void> _showAndroidUpdateDialog(AppUpdateAvailability update) async {
    if (!mounted || _androidDialogOpen) return;
    _androidDialogOpen = true;
    try {
      final locale =
          Localizations.maybeLocaleOf(context) ?? AppLocale.en.flutterLocale;
      final releaseNotes = await _releaseNotesService.fetchReleaseNotes(
        tag: update.latestTag,
        locale: locale,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _AndroidUpdateDialog(
            update: update,
            releaseNotes: releaseNotes,
            downloader: _androidApkDownloader,
            installer: _androidApkInstaller,
            externalUriLauncher: widget.externalUriLauncher,
            onDismissed: () {
              _dismissedAndroidUpdateTagInSession = update.latestTag;
            },
          );
        },
      );
    } finally {
      _androidDialogOpen = false;
    }
  }

  Future<void> _initializeNoticeSession(SharedPreferences prefs) async {
    if (_noticeSessionInitialized) return;
    _noticeSessionInitialized = true;
    _updateNoticeDismissedInSession = false;
    await prefs.setBool(
      AutoUpgradeGate.updateNoticeDismissedInSessionPrefsKey,
      false,
    );
  }

  Future<void> _showPendingApplyFailureNotice(Object error) async {
    if (!mounted || _updateNoticeDismissedInSession) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final aboutT = context.t.settings.about;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(aboutT.messages.installFailed(error: '$error')),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: aboutT.actions.manualUpdate,
          onPressed: () {
            unawaited(_openFallbackUpdateUri());
          },
        ),
      ),
    );
  }

  Future<void> _openFallbackUpdateUri() async {
    final aboutT = context.t.settings.about;
    try {
      final launcher = widget.externalUriLauncher;
      final fallbackUri = AutoUpgradeGate.fallbackUpdateUri(
        releaseRepo: _updateService.releaseRepo,
      );
      final opened = launcher != null
          ? await launcher(fallbackUri)
          : await launchUrl(
              fallbackUri,
              mode: LaunchMode.externalApplication,
            );
      if (!opened && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(aboutT.messages.openUpdateFailed),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(aboutT.messages.openUpdateFailed),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _maybeShowPassiveUpdateNotice({
    required SharedPreferences prefs,
    required AppUpdateAvailability update,
    required bool stagedReady,
  }) async {
    if (!mounted || _updateNoticeDismissedInSession) {
      return;
    }

    if (!_shouldShowUpdateNotice(
      prefs: prefs,
      latestTag: update.latestTag,
      stagedReady: stagedReady,
    )) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final updateNoticeT = context.t.settings.updateNotice;
    final commonActionsT = context.t.common.actions;
    final message = stagedReady
        ? updateNoticeT.stagedReady(version: update.latestTag)
        : (_isWindowsPlatform || _isMacosPlatform || _isLinuxPlatform) &&
                update.canSeamlessInstall
            ? updateNoticeT.seamlessAvailable(version: update.latestTag)
            : updateNoticeT.manualDownload(version: update.latestTag);
    final notNowLabel = commonActionsT.notNow;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await prefs.setString(
      AutoUpgradeGate.updateNoticeLastTagPrefsKey,
      update.latestTag,
    );
    await prefs.setInt(
      AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey,
      nowMs,
    );
    if (!mounted) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: notNowLabel,
          onPressed: () {
            unawaited(_dismissUpdateNoticeForSession(
              prefs: prefs,
              updateTag: stagedReady ? update.latestTag : null,
            ));
          },
        ),
      ),
    );
  }

  bool _shouldShowUpdateNotice({
    required SharedPreferences prefs,
    required String latestTag,
    required bool stagedReady,
  }) {
    if (_updateNoticeDismissedInSession) return false;

    if (stagedReady) {
      final readyAckTag =
          prefs.getString(AutoUpgradeGate.updateReadyAckTagPrefsKey);
      if (readyAckTag == latestTag) {
        return false;
      }
    }

    final lastTag =
        prefs.getString(AutoUpgradeGate.updateNoticeLastTagPrefsKey);
    final lastShownAtMs =
        prefs.getInt(AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey);
    if (lastTag != latestTag || lastShownAtMs == null) {
      return true;
    }

    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastShownAtMs;
    return elapsedMs >= _updateNoticeCooldown.inMilliseconds;
  }

  Future<void> _dismissUpdateNoticeForSession({
    required SharedPreferences prefs,
    required String? updateTag,
  }) async {
    _updateNoticeDismissedInSession = true;
    await prefs.setBool(
      AutoUpgradeGate.updateNoticeDismissedInSessionPrefsKey,
      true,
    );
    if (updateTag != null && updateTag.trim().isNotEmpty) {
      await prefs.setString(
          AutoUpgradeGate.updateReadyAckTagPrefsKey, updateTag);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AndroidUpdateDialog extends StatefulWidget {
  const _AndroidUpdateDialog({
    required this.update,
    required this.releaseNotes,
    required this.downloader,
    required this.installer,
    required this.externalUriLauncher,
    required this.onDismissed,
  });

  final AppUpdateAvailability update;
  final ReleaseNotesFetchResult releaseNotes;
  final AndroidApkDownloader downloader;
  final AndroidApkInstaller installer;
  final AutoUpgradeGateExternalUriLauncher? externalUriLauncher;
  final VoidCallback onDismissed;

  @override
  State<_AndroidUpdateDialog> createState() => _AndroidUpdateDialogState();
}

class _ReleaseNotesBullet extends StatelessWidget {
  const _ReleaseNotesBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Icon(
            Icons.circle,
            size: 6,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _AndroidUpdateDialogState extends State<_AndroidUpdateDialog> {
  AndroidApkDownloadProgress? _progress;
  bool _isDownloading = false;
  bool _hasAttemptedUpdate = false;
  String? _statusMessage;
  String? _errorMessage;
  AndroidApkDownloadCancelToken? _cancelToken;
  late final AndroidApkUpdateCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = AndroidApkUpdateCoordinator(
      downloader: widget.downloader,
      installer: widget.installer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final settingsT = t.settings;
    final commonT = t.common.actions;
    final notes = widget.releaseNotes.notes;
    final percent = _progress?.percent;

    return AlertDialog(
      key: const ValueKey('android_update_dialog'),
      title:
          Text(settingsT.updateDialog.title(version: widget.update.latestTag)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(settingsT.updateDialog.message),
              const SizedBox(height: 12),
              if (notes != null) ...[
                if (notes.summary.trim().isNotEmpty) ...[
                  Text(notes.summary.trim()),
                  const SizedBox(height: 8),
                ],
                for (final highlight in notes.highlights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _ReleaseNotesBullet(text: highlight),
                  ),
                for (final section in notes.sections) ...[
                  const SizedBox(height: 8),
                  Text(
                    section.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  for (final item in section.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _ReleaseNotesBullet(text: item),
                    ),
                ],
              ] else if (widget.releaseNotes.errorMessage != null) ...[
                Text(settingsT.updateDialog.releaseNotesUnavailable),
              ],
              if (_isDownloading) ...[
                const SizedBox(height: 16),
                Text(_statusMessage ?? settingsT.updateDialog.downloading),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress?.fraction),
                const SizedBox(height: 8),
                Text(
                  percent == null
                      ? settingsT.updateDialog.downloadProgressUnknown
                      : settingsT.updateDialog
                          .downloadProgress(percent: percent),
                  key: const ValueKey('android_update_progress_label'),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: ValueKey(_isDownloading
              ? 'android_update_cancel_download'
              : 'android_update_cancel'),
          onPressed: _isDownloading
              ? _cancelDownload
              : () {
                  if (!_hasAttemptedUpdate) {
                    widget.onDismissed();
                  }
                  Navigator.of(context).pop();
                },
          child: Text(commonT.cancel),
        ),
        if (!_isDownloading)
          FilledButton(
            key: const ValueKey('android_update_confirm'),
            onPressed: _startUpdate,
            child: Text(settingsT.updateDialog.updateNow),
          ),
        if (_errorMessage != null && !_isDownloading)
          TextButton(
            onPressed: _openManualUpdate,
            child: Text(settingsT.about.actions.manualUpdate),
          ),
      ],
    );
  }

  Future<void> _startUpdate() async {
    final asset = widget.update.asset;
    if (asset == null) {
      setState(() {
        _errorMessage = context.t.settings.updateDialog.downloadFailed;
      });
      return;
    }

    final cancelToken = AndroidApkDownloadCancelToken();
    _cancelToken = cancelToken;
    setState(() {
      _hasAttemptedUpdate = true;
      _isDownloading = true;
      _errorMessage = null;
      _statusMessage = context.t.settings.updateDialog.downloading;
    });

    try {
      await _coordinator.performUpdate(
        asset: asset,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
          });
        },
        cancelToken: cancelToken,
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = context.t.settings.updateDialog.installing;
      });
      Navigator.of(context).pop();
    } on AndroidApkDownloadCancelledException {
      return;
    } on AndroidApkInstallerRequiresPermissionSettingsException {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = context.t.settings.updateDialog.permissionRequired;
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = _buildErrorMessage(error);
      });
    } finally {
      _cancelToken = null;
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _buildErrorMessage(Object error) {
    if (error is AndroidApkUpdateException &&
        error.type == AndroidApkUpdateFailureType.installLaunch) {
      return context.t.settings.about.messages.openUpdateFailed;
    }
    return context.t.settings.updateDialog.downloadFailed;
  }

  Future<void> _openManualUpdate() async {
    final uri = widget.update.downloadUri;
    try {
      final launcher = widget.externalUriLauncher;
      final opened = launcher != null
          ? await launcher(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() {
          _errorMessage = context.t.settings.about.messages.openUpdateFailed;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = context.t.settings.about.messages.openUpdateFailed;
      });
    }
  }
}

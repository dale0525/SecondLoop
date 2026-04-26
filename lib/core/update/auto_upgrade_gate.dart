import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/strings.g.dart';
import 'android/android_apk_installer.dart';
import 'android/android_apk_update_coordinator.dart';
import 'app_update_flow.dart';
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
    this.androidApkUpdateCoordinator,
  });

  final Widget child;
  final AppUpdateService? updateService;
  final ReleaseNotesService? releaseNotesService;
  final bool enableInDebug;
  final AutoUpgradeGateExternalUriLauncher? externalUriLauncher;
  final AndroidApkDownloader? androidApkDownloader;
  final AndroidApkInstaller? androidApkInstaller;
  final AndroidApkUpdateCoordinator? androidApkUpdateCoordinator;

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
  Uri? _lastKnownReleasePageUri;
  bool _updateFlowDialogOpen = false;
  bool _androidCheckInFlight = false;
  String? _dismissedAndroidUpdateTagInSession;
  String? _androidInstallPermissionPendingTag;

  late final AppUpdateService _updateService;
  AppUpdateService? _ownedUpdateService;
  late final ReleaseNotesService _releaseNotesService;
  ReleaseNotesService? _ownedReleaseNotesService;
  AndroidApkDownloader? _ownedAndroidApkDownloader;
  late final AndroidApkDownloader _androidApkDownloader;
  late final AndroidApkInstaller _androidApkInstaller;
  late final AndroidApkUpdateCoordinator _androidApkUpdateCoordinator;

  bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
    _androidApkUpdateCoordinator = widget.androidApkUpdateCoordinator ??
        AndroidApkUpdateCoordinator(
          downloader: _androidApkDownloader,
          installer: _androidApkInstaller,
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
      var startupApplyResult =
          const PendingUpdateStartupResult.noPendingUpdate();
      try {
        startupApplyResult = await _updateService.applyPendingUpdateOnStartup();
      } catch (error, stackTrace) {
        pendingApplyError = error;
        debugPrint('auto_upgrade_pending_apply_skipped: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      if (startupApplyResult.shouldTerminateStartup) {
        await UpdateBadgePrefs.clear();
        return;
      }
      if (startupApplyResult.shouldPauseFurtherUpdateWork) {
        return;
      }

      try {
        final result = await _updateService.checkForUpdates();
        final update = result.update;
        if (update == null) {
          await UpdateBadgePrefs.clear();
          _androidInstallPermissionPendingTag = null;
          if (pendingApplyError != null) {
            await _showPendingApplyFailureNotice(pendingApplyError);
          }
          return;
        }

        _lastKnownReleasePageUri = update.releasePageUri;
        await UpdateBadgePrefs.setAvailableVersion(update.latestTag);
        if (pendingApplyError != null) {
          await _showPendingApplyFailureNotice(pendingApplyError);
          return;
        }

        if (_isAndroidPlatform && _isAndroidUpdateCandidate(update)) {
          if (_androidInstallPermissionPendingTag != null &&
              _androidInstallPermissionPendingTag != update.latestTag) {
            _androidInstallPermissionPendingTag = null;
          }
          if (_androidInstallPermissionPendingTag == update.latestTag) {
            if (_updateFlowDialogOpen) {
              return;
            }
            final canInstall =
                await _androidApkUpdateCoordinator.canRequestPackageInstalls();
            if (canInstall != true) {
              return;
            }
            _androidInstallPermissionPendingTag = null;
            await _showUpdateProgressOnly(
              update: update,
              useAndroidApkUpdate: true,
            );
            return;
          }
          if (_dismissedAndroidUpdateTagInSession == update.latestTag) {
            return;
          }
          await _maybeShowUpdatePrompt(
            prefs: prefs,
            update: update,
            useAndroidApkUpdate: true,
            fetchReleaseNotes: true,
          );
          return;
        }

        if (_isAndroidPlatform) {
          _androidInstallPermissionPendingTag = null;
        }
        await _maybeShowUpdatePrompt(
          prefs: prefs,
          update: update,
          useAndroidApkUpdate: false,
          fetchReleaseNotes: false,
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
    return update.canUseAndroidApkInstaller;
  }

  Future<void> _maybeShowUpdatePrompt({
    required SharedPreferences prefs,
    required AppUpdateAvailability update,
    required bool useAndroidApkUpdate,
    required bool fetchReleaseNotes,
  }) async {
    if (!mounted || (!useAndroidApkUpdate && _updateNoticeDismissedInSession)) {
      return;
    }
    if (!useAndroidApkUpdate &&
        !_shouldShowUpdateNotice(
          prefs: prefs,
          latestTag: update.latestTag,
        )) {
      return;
    }
    await _showUpdatePromptAndRunFlow(
      prefs: prefs,
      update: update,
      useAndroidApkUpdate: useAndroidApkUpdate,
      fetchReleaseNotes: fetchReleaseNotes,
    );
  }

  Future<void> _showUpdatePromptAndRunFlow({
    required SharedPreferences prefs,
    required AppUpdateAvailability update,
    required bool useAndroidApkUpdate,
    required bool fetchReleaseNotes,
  }) async {
    if (!mounted || _updateFlowDialogOpen) return;
    _updateFlowDialogOpen = true;
    try {
      final releaseNotes =
          fetchReleaseNotes ? await _fetchReleaseNotesForPrompt(update) : null;
      if (!mounted) return;
      if (!useAndroidApkUpdate) {
        await _persistUpdateNoticeCooldown(prefs, latestTag: update.latestTag);
      }
      if (!mounted) return;
      final confirmed = await showAppUpdatePromptDialog(
        context: context,
        update: update,
        releaseNotes: releaseNotes,
        message: useAndroidApkUpdate
            ? context.t.settings.updateDialog.message
            : null,
      );
      if (!mounted) return;
      if (!confirmed) {
        if (useAndroidApkUpdate) {
          _dismissedAndroidUpdateTagInSession = update.latestTag;
          _androidInstallPermissionPendingTag = null;
          return;
        }
        await _dismissUpdateNoticeForSession(
          prefs: prefs,
          latestTag: update.latestTag,
          updateTag: null,
        );
        return;
      }

      await _runUpdateFlow(
        update: update,
        useAndroidApkUpdate: useAndroidApkUpdate,
      );
    } finally {
      _updateFlowDialogOpen = false;
    }
  }

  Future<void> _showUpdateProgressOnly({
    required AppUpdateAvailability update,
    required bool useAndroidApkUpdate,
  }) async {
    if (!mounted || _updateFlowDialogOpen) return;
    _updateFlowDialogOpen = true;
    try {
      await _runUpdateFlow(
        update: update,
        useAndroidApkUpdate: useAndroidApkUpdate,
      );
    } finally {
      _updateFlowDialogOpen = false;
    }
  }

  Future<void> _runUpdateFlow({
    required AppUpdateAvailability update,
    required bool useAndroidApkUpdate,
  }) async {
    final result = await showAppUpdateProgressDialog(
      context: context,
      update: update,
      updateService: _updateService,
      androidApkUpdateCoordinator:
          useAndroidApkUpdate ? _androidApkUpdateCoordinator : null,
      externalUriLauncher: widget.externalUriLauncher,
      useAndroidApkUpdate: useAndroidApkUpdate,
      onPermissionSettingsOpened: useAndroidApkUpdate
          ? () {
              _androidInstallPermissionPendingTag = update.latestTag;
            }
          : null,
    );
    if (result == AppUpdateFlowResult.completed && useAndroidApkUpdate) {
      _dismissedAndroidUpdateTagInSession = update.latestTag;
      _androidInstallPermissionPendingTag = null;
    }
  }

  Future<ReleaseNotesFetchResult> _fetchReleaseNotesForPrompt(
    AppUpdateAvailability update,
  ) async {
    final locale =
        Localizations.maybeLocaleOf(context) ?? AppLocale.en.flutterLocale;
    try {
      return await _releaseNotesService.fetchReleaseNotes(
        tag: update.latestTag,
        locale: locale,
      );
    } catch (error, stackTrace) {
      debugPrint('android_release_notes_skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
      return ReleaseNotesFetchResult(
        errorMessage: error.toString(),
        releasePageUri: update.releasePageUri,
      );
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

  Future<void> _persistUpdateNoticeCooldown(
    SharedPreferences prefs, {
    required String latestTag,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await prefs.setString(
      AutoUpgradeGate.updateNoticeLastTagPrefsKey,
      latestTag,
    );
    await prefs.setInt(
      AutoUpgradeGate.updateNoticeLastShownAtMsPrefsKey,
      nowMs,
    );
  }

  Future<bool> _openFallbackUpdateUri({
    bool showFailureMessage = true,
  }) async {
    final aboutT = context.t.settings.about;
    try {
      final launcher = widget.externalUriLauncher;
      final fallbackUri =
          _lastKnownReleasePageUri ?? _updateService.fallbackReleasePageUri;
      final opened = launcher != null
          ? await launcher(fallbackUri)
          : await launchUrl(
              fallbackUri,
              mode: LaunchMode.externalApplication,
            );
      if (!opened && mounted) {
        if (showFailureMessage) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(aboutT.messages.openUpdateFailed),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return false;
      }
      return opened;
    } catch (_) {
      if (mounted && showFailureMessage) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(aboutT.messages.openUpdateFailed),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  bool _shouldShowUpdateNotice({
    required SharedPreferences prefs,
    required String latestTag,
  }) {
    if (_updateNoticeDismissedInSession) return false;

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
    required String latestTag,
    required String? updateTag,
  }) async {
    await _persistUpdateNoticeCooldown(prefs, latestTag: latestTag);
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

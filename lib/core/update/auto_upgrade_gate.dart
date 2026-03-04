import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/strings.g.dart';
import 'app_update_service.dart';
import 'update_badge_prefs.dart';

class AutoUpgradeGate extends StatefulWidget {
  const AutoUpgradeGate({
    super.key,
    required this.child,
    this.updateService,
    this.enableInDebug = false,
  });

  final Widget child;
  final AppUpdateService? updateService;
  final bool enableInDebug;

  static const updateNoticeLastTagPrefsKey = 'update_notice_last_tag_v1';
  static const updateNoticeLastShownAtMsPrefsKey =
      'update_notice_last_shown_at_ms_v1';
  static const updateNoticeDismissedInSessionPrefsKey =
      'update_notice_dismissed_in_session_v1';
  static const updateReadyAckTagPrefsKey = 'update_ready_ack_tag_v1';

  @override
  State<AutoUpgradeGate> createState() => _AutoUpgradeGateState();
}

class _AutoUpgradeGateState extends State<AutoUpgradeGate> {
  static const _updateNoticeCooldown = Duration(hours: 24);

  bool _checkScheduled = false;
  bool _noticeSessionInitialized = false;
  bool _updateNoticeDismissedInSession = false;

  late final AppUpdateService _updateService;
  AppUpdateService? _ownedUpdateService;
  bool get _isWindowsPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeAutoUpgrade());
    });
  }

  @override
  void dispose() {
    _ownedUpdateService?.dispose();
    super.dispose();
  }

  Future<void> _maybeAutoUpgrade() async {
    if (!kReleaseMode && !widget.enableInDebug) return;

    final prefs = await SharedPreferences.getInstance();
    await _initializeNoticeSession(prefs);

    try {
      await _updateService.applyPendingUpdateOnStartup();
    } catch (error, stackTrace) {
      debugPrint('auto_upgrade_pending_apply_skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      final result = await _updateService.checkForUpdates();
      final update = result.update;
      if (update == null) {
        await UpdateBadgePrefs.clear();
        return;
      }

      if (_isWindowsPlatform) {
        await UpdateBadgePrefs.clear();
        if (update.canStageForNextLaunch || update.canSeamlessInstall) {
          await _updateService.stageUpdateForNextLaunch(update);
        }
        return;
      }

      await UpdateBadgePrefs.setAvailableVersion(update.latestTag);
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

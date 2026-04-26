import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/strings.g.dart';
import 'android/android_apk_installer.dart';
import 'android/android_apk_update_coordinator.dart';
import 'app_update_service.dart';
import 'release_notes_service.dart';

typedef AppUpdateFlowExternalUriLauncher = Future<bool> Function(Uri uri);

enum AppUpdateFlowResult {
  completed,
  cancelled,
}

Future<bool> showAppUpdatePromptDialog({
  required BuildContext context,
  required AppUpdateAvailability update,
  ReleaseNotesFetchResult? releaseNotes,
  String? message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _AppUpdatePromptDialog(
      update: update,
      releaseNotes: releaseNotes,
      message: message,
    ),
  );
  return confirmed == true;
}

Future<AppUpdateFlowResult> showAppUpdateProgressDialog({
  required BuildContext context,
  required AppUpdateAvailability update,
  required AppUpdateService updateService,
  AndroidApkUpdateCoordinator? androidApkUpdateCoordinator,
  AppUpdateFlowExternalUriLauncher? externalUriLauncher,
  bool useAndroidApkUpdate = false,
  VoidCallback? onPermissionSettingsOpened,
}) async {
  final result = await showDialog<AppUpdateFlowResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _AppUpdateProgressDialog(
      update: update,
      updateService: updateService,
      androidApkUpdateCoordinator: androidApkUpdateCoordinator,
      externalUriLauncher: externalUriLauncher,
      useAndroidApkUpdate: useAndroidApkUpdate,
      onPermissionSettingsOpened: onPermissionSettingsOpened,
    ),
  );
  return result ?? AppUpdateFlowResult.cancelled;
}

class _AppUpdatePromptDialog extends StatelessWidget {
  const _AppUpdatePromptDialog({
    required this.update,
    required this.releaseNotes,
    required this.message,
  });

  final AppUpdateAvailability update;
  final ReleaseNotesFetchResult? releaseNotes;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final notes = releaseNotes?.notes;
    return AlertDialog(
      key: const ValueKey('update_prompt_dialog'),
      title: Text(t.settings.updateDialog.title(version: update.latestTag)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message ?? _defaultPromptMessage(context, update)),
              if (notes != null) ...[
                if (notes.summary.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(notes.summary.trim()),
                ],
                for (final highlight in notes.highlights)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _ReleaseNotesBullet(text: highlight),
                  ),
                for (final section in notes.sections) ...[
                  const SizedBox(height: 12),
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
              ] else if (releaseNotes?.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(t.settings.updateDialog.releaseNotesUnavailable),
              ],
            ],
          ),
        ),
      ),
      actions: [
        KeyedSubtree(
          key: const ValueKey('update_prompt_ignore'),
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.common.actions.ignore),
          ),
        ),
        KeyedSubtree(
          key: const ValueKey('update_prompt_update'),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.settings.updateDialog.updateNow),
          ),
        ),
      ],
    );
  }

  String _defaultPromptMessage(
    BuildContext context,
    AppUpdateAvailability update,
  ) {
    final t = context.t.settings;
    if (update.canSeamlessInstall) {
      return t.updateNotice.seamlessAvailable(version: update.latestTag);
    }
    if (update.canStageForNextLaunch) {
      return t.about.status.availableStaged(version: update.latestTag);
    }
    return t.updateNotice.manualDownload(version: update.latestTag);
  }
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

class _AppUpdateProgressDialog extends StatefulWidget {
  const _AppUpdateProgressDialog({
    required this.update,
    required this.updateService,
    required this.androidApkUpdateCoordinator,
    required this.externalUriLauncher,
    required this.useAndroidApkUpdate,
    required this.onPermissionSettingsOpened,
  });

  final AppUpdateAvailability update;
  final AppUpdateService updateService;
  final AndroidApkUpdateCoordinator? androidApkUpdateCoordinator;
  final AppUpdateFlowExternalUriLauncher? externalUriLauncher;
  final bool useAndroidApkUpdate;
  final VoidCallback? onPermissionSettingsOpened;

  @override
  State<_AppUpdateProgressDialog> createState() =>
      _AppUpdateProgressDialogState();
}

class _AppUpdateProgressDialogState extends State<_AppUpdateProgressDialog>
    with WidgetsBindingObserver {
  AndroidApkDownloadProgress? _progress;
  bool _isRunning = false;
  bool _awaitingInstallPermission = false;
  bool _applyingStagedUpdate = false;
  String? _statusMessage;
  String? _errorMessage;
  AndroidApkDownloadCancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startUpdate());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_awaitingInstallPermission || !widget.useAndroidApkUpdate) return;
    unawaited(_retryAndroidInstallAfterPermissionGrant());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final percent = _progress?.percent;
    final showProgress = _isRunning;
    final statusMessage = _errorMessage == null
        ? _statusMessage ?? t.settings.about.messages.installStarting
        : _statusMessage;
    return AlertDialog(
      key: ValueKey(widget.useAndroidApkUpdate
          ? 'android_update_dialog'
          : 'update_progress_dialog'),
      title: Text(t.settings.updateDialog.title(
        version: widget.update.latestTag,
      )),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusMessage != null) Text(statusMessage),
            if (showProgress) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                key: const ValueKey('update_progress_bar'),
                value: widget.useAndroidApkUpdate ? _progress?.fraction : null,
              ),
              if (widget.useAndroidApkUpdate) ...[
                const SizedBox(height: 8),
                Text(
                  percent == null
                      ? t.settings.updateDialog.downloadProgressUnknown
                      : t.settings.updateDialog.downloadProgress(
                          percent: percent,
                        ),
                  key: const ValueKey('android_update_progress_label'),
                ),
              ],
            ],
            if (_errorMessage != null) ...[
              if (statusMessage != null) const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.useAndroidApkUpdate && _isRunning)
          TextButton(
            key: const ValueKey('android_update_cancel_download'),
            onPressed: _cancelUpdate,
            child: Text(t.common.actions.cancel),
          )
        else if (!_isRunning)
          TextButton(
            key: const ValueKey('android_update_cancel'),
            onPressed: () {
              Navigator.of(context).pop(AppUpdateFlowResult.cancelled);
            },
            child: Text(t.common.actions.cancel),
          ),
        if (!_isRunning && _errorMessage != null)
          FilledButton(
            key: const ValueKey('android_update_confirm'),
            onPressed: _startUpdate,
            child: Text(t.common.actions.retry),
          ),
        if (!_isRunning && _errorMessage != null)
          TextButton(
            key: const ValueKey('android_update_manual'),
            onPressed: _openManualUpdate,
            child: Text(t.settings.about.actions.manualUpdate),
          ),
      ],
    );
  }

  Future<void> _retryAndroidInstallAfterPermissionGrant() async {
    final coordinator = widget.androidApkUpdateCoordinator;
    if (coordinator == null) return;
    final canInstall = await coordinator.canRequestPackageInstalls();
    if (!mounted || canInstall != true) return;
    await _startUpdate();
  }

  Future<void> _startUpdate() async {
    if (_isRunning) return;
    final useAndroidApkUpdate = widget.useAndroidApkUpdate;
    final cancelToken =
        useAndroidApkUpdate ? AndroidApkDownloadCancelToken() : null;
    _cancelToken = cancelToken;
    setState(() {
      _isRunning = true;
      _awaitingInstallPermission = false;
      _applyingStagedUpdate = false;
      _progress = null;
      _errorMessage = null;
      _statusMessage = _initialStatusMessage(context);
    });

    try {
      if (useAndroidApkUpdate) {
        await _performAndroidApkUpdate(cancelToken);
      } else {
        await _performManagedUpdate();
      }
      if (!mounted) return;
      Navigator.of(context).pop(AppUpdateFlowResult.completed);
    } on AndroidApkDownloadCancelledException {
      if (!mounted) return;
      Navigator.of(context).pop(AppUpdateFlowResult.cancelled);
    } on AndroidApkInstallerRequiresPermissionSettingsException {
      if (!mounted) return;
      widget.onPermissionSettingsOpened?.call();
      setState(() {
        _isRunning = false;
        _awaitingInstallPermission = true;
        _applyingStagedUpdate = false;
        _errorMessage = context.t.settings.updateDialog.permissionRequired;
        _statusMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      final errorMessage = _buildErrorMessage(error);
      setState(() {
        _isRunning = false;
        _awaitingInstallPermission = false;
        _applyingStagedUpdate = false;
        _errorMessage = errorMessage;
        _statusMessage = null;
      });
    } finally {
      if (identical(_cancelToken, cancelToken)) {
        _cancelToken = null;
      }
    }
  }

  Future<void> _performAndroidApkUpdate(
    AndroidApkDownloadCancelToken? cancelToken,
  ) async {
    final asset = widget.update.asset;
    final coordinator = widget.androidApkUpdateCoordinator;
    if (asset == null || coordinator == null) {
      throw StateError('android_apk_update_unavailable');
    }
    await coordinator.performUpdate(
      asset: asset,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _statusMessage = context.t.settings.updateDialog.downloading;
        });
      },
      cancelToken: cancelToken,
    );
    if (!mounted) return;
    setState(() {
      _statusMessage = context.t.settings.updateDialog.installing;
    });
  }

  Future<void> _performManagedUpdate() async {
    final update = widget.update;
    if (update.canSeamlessInstall) {
      await widget.updateService.installAndRestart(update);
      return;
    }
    if (update.canStageForNextLaunch) {
      setState(() {
        _statusMessage = context.t.settings.about.messages.stageStarting;
      });
      await widget.updateService.stageUpdateForNextLaunch(update);
      if (!mounted) return;
      setState(() {
        _applyingStagedUpdate = true;
        _statusMessage = context.t.settings.updateDialog.installing;
      });
      await widget.updateService.applyStagedUpdateAndRestart();
      return;
    }
    final opened = await _openReleasePage();
    if (!opened) {
      throw StateError('open_update_page_failed');
    }
  }

  void _cancelUpdate() {
    _cancelToken?.cancel();
  }

  String _initialStatusMessage(BuildContext context) {
    if (widget.useAndroidApkUpdate) {
      return context.t.settings.updateDialog.downloading;
    }
    if (widget.update.canStageForNextLaunch) {
      return context.t.settings.about.messages.stageStarting;
    }
    if (!widget.update.canSeamlessInstall) {
      return context.t.settings.updateNotice.manualDownload(
        version: widget.update.latestTag,
      );
    }
    return context.t.settings.about.messages.installStarting;
  }

  String _buildErrorMessage(Object error) {
    if (error is AndroidApkUpdateException &&
        error.type == AndroidApkUpdateFailureType.installLaunch) {
      return context.t.settings.about.messages.openUpdateFailed;
    }
    if (widget.useAndroidApkUpdate) {
      return context.t.settings.updateDialog.downloadFailed;
    }
    if (widget.update.canStageForNextLaunch) {
      if (_applyingStagedUpdate) {
        return context.t.settings.about.messages.installFailed(error: '$error');
      }
      return context.t.settings.about.messages.stageFailed(error: '$error');
    }
    if (widget.update.canSeamlessInstall) {
      return context.t.settings.about.messages.installFailed(error: '$error');
    }
    return context.t.settings.about.messages.openUpdateFailed;
  }

  Future<void> _openManualUpdate() async {
    final opened = await _openReleasePage();
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop(AppUpdateFlowResult.completed);
      return;
    }
    setState(() {
      _errorMessage = context.t.settings.about.messages.openUpdateFailed;
    });
  }

  Future<bool> _openReleasePage() async {
    try {
      final launcher = widget.externalUriLauncher;
      if (launcher != null) {
        return await launcher(widget.update.releasePageUri);
      }
      return await launchUrl(
        widget.update.releasePageUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

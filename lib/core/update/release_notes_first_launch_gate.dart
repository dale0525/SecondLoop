import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_service.dart';
import 'release_notes_service.dart';

typedef RuntimeVersionLoader = Future<AppRuntimeVersion> Function();
typedef ExternalUriLauncher = Future<bool> Function(Uri uri);

class ReleaseNotesFirstLaunchGate extends StatefulWidget {
  const ReleaseNotesFirstLaunchGate({
    super.key,
    required this.child,
    this.releaseNotesService,
    this.currentVersionLoader,
    this.externalUriLauncher,
    this.enableInDebug = false,
  });

  static const lastShownVersionPrefsKey = 'release_notes_last_shown_version_v1';

  final Widget child;
  final ReleaseNotesService? releaseNotesService;
  final RuntimeVersionLoader? currentVersionLoader;
  final ExternalUriLauncher? externalUriLauncher;
  final bool enableInDebug;

  @override
  State<ReleaseNotesFirstLaunchGate> createState() =>
      _ReleaseNotesFirstLaunchGateState();
}

class _ReleaseNotesFirstLaunchGateState
    extends State<ReleaseNotesFirstLaunchGate> {
  bool _checkScheduled = false;
  bool _dialogShowing = false;

  late final ReleaseNotesService _releaseNotesService;
  ReleaseNotesService? _ownedService;

  @override
  void initState() {
    super.initState();
    final providedService = widget.releaseNotesService;
    if (providedService != null) {
      _releaseNotesService = providedService;
    } else {
      final createdService = ReleaseNotesService();
      _releaseNotesService = createdService;
      _ownedService = createdService;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowReleaseNotes());
    });
  }

  @override
  void dispose() {
    _ownedService?.dispose();
    super.dispose();
  }

  Future<void> _maybeShowReleaseNotes() async {
    if (!kReleaseMode && !widget.enableInDebug) {
      return;
    }

    final versionLoader = widget.currentVersionLoader ?? _loadCurrentVersion;
    final runtimeVersion = await versionLoader();
    final currentVersion = runtimeVersion.display;

    final prefs = await SharedPreferences.getInstance();
    final lastShown = prefs.getString(
      ReleaseNotesFirstLaunchGate.lastShownVersionPrefsKey,
    );
    if (lastShown == currentVersion) return;
    if (!mounted) return;

    final locale =
        Localizations.maybeLocaleOf(context) ?? const Locale('en', 'US');
    final tag = normalizeReleaseTag(runtimeVersion.version);

    ReleaseNotesFetchResult result;
    if (tag == null) {
      result = const ReleaseNotesFetchResult(errorMessage: 'invalid_tag');
    } else {
      result = await _releaseNotesService.fetchReleaseNotes(
          tag: tag, locale: locale);
    }

    if (!mounted || _dialogShowing) return;
    _dialogShowing = true;
    await showDialog<void>(
      context: context,
      builder: (context) => _ReleaseNotesDialog(
        result: result,
        appVersion: runtimeVersion.version,
        closeVersion: currentVersion,
        launcher: widget.externalUriLauncher,
      ),
    );
    _dialogShowing = false;

    await prefs.setString(
      ReleaseNotesFirstLaunchGate.lastShownVersionPrefsKey,
      currentVersion,
    );
  }

  Future<AppRuntimeVersion> _loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return AppRuntimeVersion(
        version: info.version,
        buildNumber: info.buildNumber,
      );
    } catch (_) {
      return const AppRuntimeVersion(version: '0.0.0', buildNumber: '0');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ReleaseNotesDialog extends StatelessWidget {
  const _ReleaseNotesDialog({
    required this.result,
    required this.appVersion,
    required this.closeVersion,
    required this.launcher,
  });

  final ReleaseNotesFetchResult result;
  final String appVersion;
  final String closeVersion;
  final ExternalUriLauncher? launcher;

  @override
  Widget build(BuildContext context) {
    final text = _ReleaseNotesText.of(Localizations.localeOf(context));
    final notes = result.notes;

    return AlertDialog(
      key: const ValueKey('release_notes_dialog'),
      title: Text(text.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text.updatedTo(
                  version: notes?.version.trim().isNotEmpty == true
                      ? notes!.version
                      : 'v$appVersion')),
              const SizedBox(height: 8),
              if (notes == null) ...[
                Text(
                  text.unavailable(
                    errorMessage: result.errorMessage,
                  ),
                ),
              ] else ...[
                if (notes.summary.trim().isNotEmpty) ...[
                  Text(notes.summary.trim()),
                  const SizedBox(height: 8),
                ],
                if (notes.highlights.isNotEmpty) ...[
                  Text(
                    text.highlights,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  for (final highlight in notes.highlights)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(_formatBullet(highlight)),
                    ),
                  const SizedBox(height: 8),
                ],
                for (final section in notes.sections) ...[
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
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(_formatBullet(item)),
                    ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (result.releasePageUri != null)
          TextButton(
            onPressed: () =>
                unawaited(_openReleasePage(context, result.releasePageUri!)),
            child: Text(text.openFullReleaseNotes),
          ),
        FilledButton(
          key: const ValueKey('release_notes_close'),
          onPressed: () => Navigator.of(context).pop(closeVersion),
          child: Text(text.close),
        ),
      ],
    );
  }

  String _formatBullet(String value) => '\u2022 $value';

  Future<void> _openReleasePage(BuildContext context, Uri uri) async {
    final text = _ReleaseNotesText.of(Localizations.localeOf(context));
    try {
      final open = launcher;
      final launched = open != null
          ? await open(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(text.openFailed),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text.openFailed),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

class _ReleaseNotesText {
  const _ReleaseNotesText._(this._isZh);

  final bool _isZh;

  static _ReleaseNotesText of(Locale locale) {
    final languageCode = locale.languageCode.toLowerCase();
    return _ReleaseNotesText._(languageCode.startsWith('zh'));
  }

  String get title => _isZh ? '更新日志' : 'What\'s new';

  String updatedTo({required String version}) =>
      _isZh ? '已更新到 $version' : 'Updated to $version';

  String get highlights => _isZh ? '重点更新' : 'Highlights';

  String unavailable({String? errorMessage}) {
    if (_isZh) {
      if (errorMessage == null || errorMessage.trim().isEmpty) {
        return '更新日志暂时不可用，你可以稍后查看完整发布说明。';
      }
      return '更新日志暂时不可用（$errorMessage）。你可以稍后查看完整发布说明。';
    }

    if (errorMessage == null || errorMessage.trim().isEmpty) {
      return 'Release notes are not available right now. You can open the full release notes later.';
    }
    return 'Release notes are not available right now ($errorMessage). You can open the full release notes later.';
  }

  String get openFullReleaseNotes =>
      _isZh ? '查看完整发布说明' : 'Open full release notes';

  String get close => _isZh ? '我知道了' : 'Got it';

  String get openFailed =>
      _isZh ? '无法打开发布说明页面' : 'Unable to open release notes page';
}

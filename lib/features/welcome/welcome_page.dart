import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/settings/ai_settings_page.dart';
import '../../features/settings/sync_settings_page.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import 'welcome_status.dart';

typedef WelcomeGuideUriLauncher = Future<bool> Function(Uri uri);

class WelcomePage extends StatefulWidget {
  const WelcomePage({
    super.key,
    required this.onSkipForNow,
    required this.onFinishSetup,
    this.statusLoader = loadWelcomeGuideStatus,
    this.uriLauncher,
  });

  final VoidCallback onSkipForNow;
  final VoidCallback onFinishSetup;
  final WelcomeGuideStatusLoader statusLoader;
  final WelcomeGuideUriLauncher? uriLauncher;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  static const _kPermissionLaunchFailedKey =
      ValueKey('welcome_guide_permission_launch_failed');

  bool _statusLoaded = false;
  WelcomeGuideStatus _status = const WelcomeGuideStatus(
    aiReady: false,
    syncReady: false,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_statusLoaded) return;
    _statusLoaded = true;
    unawaited(_reloadStatus());
  }

  Future<void> _reloadStatus() async {
    WelcomeGuideStatus status;
    try {
      status = await widget.statusLoader(context);
    } catch (_) {
      status = const WelcomeGuideStatus(aiReady: false, syncReady: false);
    }

    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _openAiSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AiSettingsPage(),
      ),
    );
    if (!mounted) return;
    await _reloadStatus();
  }

  Future<void> _openSyncSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SyncSettingsPage(),
      ),
    );
    if (!mounted) return;
    await _reloadStatus();
  }

  Future<void> _openPermissionSettings(_PermissionItem item) async {
    for (final uri in _permissionSettingsUris(item)) {
      try {
        final launched = await _launch(uri);
        if (launched) {
          return;
        }
      } catch (_) {
        // Try next candidate URI.
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: _kPermissionLaunchFailedKey,
        content: Text(context.t.welcomeGuide.permissions.openFailed),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool> _launch(Uri uri) async {
    final launcher = widget.uriLauncher;
    if (launcher != null) {
      return launcher(uri);
    }

    return launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  List<Uri> _permissionSettingsUris(_PermissionItem item) {
    if (kIsWeb) return const <Uri>[];

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return <Uri>[Uri.parse('app-settings:')];
      case TargetPlatform.macOS:
        return _macOsPermissionUris(item);
      case TargetPlatform.windows:
        return _windowsPermissionUris(item);
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const <Uri>[];
    }
  }

  List<Uri> _macOsPermissionUris(_PermissionItem item) {
    return switch (item) {
      _PermissionItem.microphone => <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ],
      _PermissionItem.speech => <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition',
          ),
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.speech?Dictation',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ],
      _PermissionItem.notifications => <Uri>[
          Uri.parse(
              'x-apple.systempreferences:com.apple.preference.notifications'),
          Uri.parse('x-apple.systempreferences:'),
        ],
    };
  }

  List<Uri> _windowsPermissionUris(_PermissionItem item) {
    return switch (item) {
      _PermissionItem.microphone => <Uri>[
          Uri.parse('ms-settings:privacy-microphone'),
          Uri.parse('ms-settings:sound'),
        ],
      _PermissionItem.speech => <Uri>[
          Uri.parse('ms-settings:privacy-speech'),
          Uri.parse('ms-settings:speech'),
        ],
      _PermissionItem.notifications => <Uri>[
          Uri.parse('ms-settings:notifications'),
          Uri.parse('ms-settings:quiethours'),
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.welcomeGuide;
    return Scaffold(
      key: const ValueKey('welcome_guide_page'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      key: const ValueKey('welcome_guide_header_title'),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.subtitle,
                      key: const ValueKey('welcome_guide_header_subtitle'),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    _WelcomeGuideCard(
                      cardKey: const ValueKey('welcome_guide_card_ai'),
                      title: t.ai.title,
                      description: t.ai.description,
                      statusLabel: _status.aiReady
                          ? t.ai.statusReady
                          : t.ai.statusNotSet,
                      statusKey: ValueKey(
                        _status.aiReady
                            ? 'welcome_guide_ai_status_ready'
                            : 'welcome_guide_ai_status_not_set',
                      ),
                      actionKey: const ValueKey('welcome_guide_card_ai_open'),
                      actionLabel: t.ai.open,
                      onActionTap: () => unawaited(_openAiSettings()),
                    ),
                    const SizedBox(height: 12),
                    _WelcomeGuideCard(
                      cardKey: const ValueKey('welcome_guide_card_sync'),
                      title: t.sync.title,
                      description: t.sync.description,
                      statusLabel: _status.syncReady
                          ? t.sync.statusReady
                          : t.sync.statusNotSet,
                      statusKey: ValueKey(
                        _status.syncReady
                            ? 'welcome_guide_sync_status_ready'
                            : 'welcome_guide_sync_status_not_set',
                      ),
                      actionKey: const ValueKey('welcome_guide_card_sync_open'),
                      actionLabel: t.sync.open,
                      onActionTap: () => unawaited(_openSyncSettings()),
                    ),
                    const SizedBox(height: 12),
                    SlSurface(
                      key: const ValueKey('welcome_guide_card_permissions'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.permissions.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                _StatusBadge(
                                  label: t.permissions.statusNeedsReview,
                                  badgeKey: const ValueKey(
                                    'welcome_guide_permissions_status_needs_review',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t.permissions.description,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            _PermissionTile(
                              tileKey: const ValueKey(
                                  'welcome_guide_permission_microphone'),
                              icon: Icons.mic_none_rounded,
                              label: t.permissions.microphone,
                              onTap: () => unawaited(
                                _openPermissionSettings(
                                    _PermissionItem.microphone),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PermissionTile(
                              tileKey: const ValueKey(
                                  'welcome_guide_permission_speech'),
                              icon: Icons.record_voice_over_outlined,
                              label: t.permissions.speech,
                              onTap: () => unawaited(
                                _openPermissionSettings(_PermissionItem.speech),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PermissionTile(
                              tileKey: const ValueKey(
                                  'welcome_guide_permission_notifications'),
                              icon: Icons.notifications_none_rounded,
                              label: t.permissions.notifications,
                              onTap: () => unawaited(
                                _openPermissionSettings(
                                    _PermissionItem.notifications),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('welcome_guide_skip'),
                    onPressed: widget.onSkipForNow,
                    child: Text(t.actions.skip),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('welcome_guide_finish'),
                      onPressed: widget.onFinishSetup,
                      child: Text(t.actions.finish),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeGuideCard extends StatelessWidget {
  const _WelcomeGuideCard({
    required this.cardKey,
    required this.title,
    required this.description,
    required this.statusLabel,
    required this.statusKey,
    required this.actionKey,
    required this.actionLabel,
    required this.onActionTap,
  });

  final Key cardKey;
  final String title;
  final String description;
  final String statusLabel;
  final Key statusKey;
  final Key actionKey;
  final String actionLabel;
  final VoidCallback onActionTap;

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                _StatusBadge(label: statusLabel, badgeKey: statusKey),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: actionKey,
              onPressed: onActionTap,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.badgeKey,
  });

  final String label;
  final Key badgeKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          key: badgeKey,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: tileKey,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label),
            ),
            const Icon(Icons.open_in_new_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

enum _PermissionItem {
  microphone,
  speech,
  notifications,
}

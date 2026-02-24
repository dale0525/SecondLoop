import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../i18n/strings.g.dart';
import '../settings/ai_settings_page.dart';
import '../settings/sync_settings_page.dart';

typedef WelcomeStatusLoader = Future<WelcomeGuideStatus> Function(
  BuildContext context,
);
typedef WelcomeExternalUriLauncher = Future<bool> Function(Uri uri);

class WelcomeGuideStatus {
  const WelcomeGuideStatus({
    required this.aiReady,
    required this.syncReady,
  });

  final bool aiReady;
  final bool syncReady;
}

enum _WelcomeStatusChipKind {
  notSet,
  ready,
  needsReview,
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({
    super.key,
    required this.onSkip,
    required this.onFinish,
    this.statusLoader,
    this.externalUriLauncher,
  });

  final VoidCallback onSkip;
  final VoidCallback onFinish;
  final WelcomeStatusLoader? statusLoader;
  final WelcomeExternalUriLauncher? externalUriLauncher;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _statusLoaded = false;
  bool _didScheduleStatusLoad = false;
  WelcomeGuideStatus _status =
      const WelcomeGuideStatus(aiReady: false, syncReady: false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didScheduleStatusLoad) return;
    _didScheduleStatusLoad = true;
    unawaited(_loadStatus());
  }

  Future<void> _loadStatus() async {
    final loader = widget.statusLoader ?? _resolveStatusFromApp;
    WelcomeGuideStatus next;
    try {
      next = await loader(context);
    } catch (_) {
      next = const WelcomeGuideStatus(aiReady: false, syncReady: false);
    }
    if (!mounted) return;
    setState(() {
      _status = next;
      _statusLoaded = true;
    });
  }

  static Future<WelcomeGuideStatus> _resolveStatusFromApp(
    BuildContext context,
  ) async {
    var aiReady = false;
    try {
      final backend = AppBackendScope.maybeOf(context);
      final session = SessionScope.maybeOf(context);
      if (backend != null && session != null) {
        final cloudScope = CloudAuthScope.maybeOf(context);
        final gatewayConfig =
            cloudScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
        final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
            SubscriptionStatus.unknown;
        String? cloudIdToken;
        try {
          cloudIdToken = await cloudScope?.controller.getIdToken();
        } catch (_) {
          cloudIdToken = null;
        }

        final route = await decideAskAiRoute(
          backend,
          session.sessionKey,
          cloudIdToken: cloudIdToken,
          cloudGatewayBaseUrl: gatewayConfig.baseUrl,
          subscriptionStatus: subscriptionStatus,
        );
        aiReady = route != AskAiRouteKind.needsSetup;
      }
    } catch (_) {
      aiReady = false;
    }

    var syncReady = false;
    try {
      final sync = await SyncConfigStore().loadConfiguredSync();
      syncReady = sync != null;
    } catch (_) {
      syncReady = false;
    }

    return WelcomeGuideStatus(aiReady: aiReady, syncReady: syncReady);
  }

  Future<void> _openPermissionSettings(
    List<Uri> uris,
  ) async {
    final launcher = widget.externalUriLauncher;
    for (final uri in uris) {
      try {
        final opened = launcher != null
            ? await launcher(uri)
            : await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (opened) return;
      } catch (_) {}
    }
    if (!mounted) return;
    final t = context.t.welcomeGuide;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.messages.openSettingsFailed),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<Uri> _microphoneSettingsUris() {
    if (kIsWeb) return const <Uri>[];

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return <Uri>[Uri.parse('app-settings:')];
      case TargetPlatform.macOS:
        return <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ];
      case TargetPlatform.windows:
        return <Uri>[
          Uri.parse('ms-settings:privacy-microphone'),
          Uri.parse('ms-settings:sound'),
        ];
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const <Uri>[];
    }
  }

  List<Uri> _speechSettingsUris() {
    if (kIsWeb) return const <Uri>[];

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return <Uri>[Uri.parse('app-settings:')];
      case TargetPlatform.macOS:
        return <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition',
          ),
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.speech?Dictation',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ];
      case TargetPlatform.windows:
        return <Uri>[
          Uri.parse('ms-settings:privacy-speech'),
          Uri.parse('ms-settings:speech'),
        ];
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const <Uri>[];
    }
  }

  List<Uri> _notificationSettingsUris() {
    if (kIsWeb) return const <Uri>[];

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return <Uri>[Uri.parse('app-settings:')];
      case TargetPlatform.macOS:
        return <Uri>[
          Uri.parse(
              'x-apple.systempreferences:com.apple.preference.notifications'),
          Uri.parse('x-apple.systempreferences:'),
        ];
      case TargetPlatform.windows:
        return <Uri>[
          Uri.parse('ms-settings:notifications'),
        ];
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const <Uri>[];
    }
  }

  Widget _statusChip(
    _WelcomeStatusChipKind kind,
  ) {
    final t = context.t.welcomeGuide;
    final colorScheme = Theme.of(context).colorScheme;
    final (String text, Color bg, Color fg) = switch (kind) {
      _WelcomeStatusChipKind.notSet => (
          t.status.notSet,
          colorScheme.surfaceVariant,
          colorScheme.onSurfaceVariant,
        ),
      _WelcomeStatusChipKind.ready => (
          t.status.ready,
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
        ),
      _WelcomeStatusChipKind.needsReview => (
          t.status.needsReview,
          colorScheme.tertiaryContainer,
          colorScheme.onTertiaryContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }

  Widget _setupCard({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required _WelcomeStatusChipKind status,
    required VoidCallback onOpen,
  }) {
    return Card(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: onOpen,
                    child: Text(context.t.welcomeGuide.actions.open),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _statusChip(status),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.welcomeGuide;
    final aiStatus = _status.aiReady
        ? _WelcomeStatusChipKind.ready
        : _WelcomeStatusChipKind.notSet;
    final syncStatus = _status.syncReady
        ? _WelcomeStatusChipKind.ready
        : _WelcomeStatusChipKind.notSet;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey('welcome_page'),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          children: [
            Text(
              t.title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(t.subtitle),
            const SizedBox(height: 16),
            _setupCard(
              key: const ValueKey('welcome_card_ai'),
              icon: Icons.auto_awesome_outlined,
              title: t.cards.ai.title,
              subtitle: t.cards.ai.subtitle,
              status: aiStatus,
              onOpen: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AiSettingsPage(),
                  ),
                );
              },
            ),
            _setupCard(
              key: const ValueKey('welcome_card_sync'),
              icon: Icons.sync_outlined,
              title: t.cards.sync.title,
              subtitle: t.cards.sync.subtitle,
              status: syncStatus,
              onOpen: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SyncSettingsPage(),
                  ),
                );
              },
            ),
            Card(
              key: const ValueKey('welcome_card_permissions'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.privacy_tip_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.cards.permissions.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(t.cards.permissions.subtitle),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(_WelcomeStatusChipKind.needsReview),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('welcome_permission_microphone'),
                          onPressed: () => unawaited(
                            _openPermissionSettings(_microphoneSettingsUris()),
                          ),
                          icon: const Icon(Icons.mic_none_outlined),
                          label: Text(t.permissionItems.microphone),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('welcome_permission_speech'),
                          onPressed: () => unawaited(
                            _openPermissionSettings(_speechSettingsUris()),
                          ),
                          icon: const Icon(Icons.record_voice_over_outlined),
                          label: Text(t.permissionItems.speech),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey(
                              'welcome_permission_notifications'),
                          onPressed: () => unawaited(
                            _openPermissionSettings(
                                _notificationSettingsUris()),
                          ),
                          icon: const Icon(Icons.notifications_outlined),
                          label: Text(t.permissionItems.notifications),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (!_statusLoaded)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('welcome_skip'),
                    onPressed: widget.onSkip,
                    child: Text(t.actions.skip),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('welcome_finish'),
                    onPressed: widget.onFinish,
                    child: Text(t.actions.finish),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

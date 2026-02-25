import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const _kPermissionChannel = MethodChannel('secondloop/permissions');

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

  String _localized({
    required String zh,
    required String en,
  }) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode.toLowerCase().startsWith('zh') ? zh : en;
  }

  List<_PermissionTileData> _permissionTiles() {
    if (kIsWeb) {
      return const <_PermissionTileData>[];
    }

    final items = switch (defaultTargetPlatform) {
      TargetPlatform.android => <_PermissionItem>[
          _PermissionItem.microphone,
          _PermissionItem.notifications,
          _PermissionItem.exactAlarm,
          _PermissionItem.location,
          _PermissionItem.autoStart,
          _PermissionItem.batteryUnrestricted,
        ],
      TargetPlatform.iOS => <_PermissionItem>[
          _PermissionItem.microphone,
          _PermissionItem.notifications,
          _PermissionItem.location,
        ],
      TargetPlatform.macOS => <_PermissionItem>[
          _PermissionItem.microphone,
          _PermissionItem.notifications,
          _PermissionItem.autoStart,
        ],
      TargetPlatform.windows => <_PermissionItem>[
          _PermissionItem.microphone,
          _PermissionItem.notifications,
          _PermissionItem.autoStart,
        ],
      TargetPlatform.linux => const <_PermissionItem>[],
      TargetPlatform.fuchsia => const <_PermissionItem>[],
    };

    return items
        .map(
          (item) => _PermissionTileData(
            item: item,
            key: ValueKey('welcome_guide_permission_${item.keySuffix}'),
            icon: _permissionIcon(item),
            label: _permissionLabel(item),
            reason: _permissionReason(item),
          ),
        )
        .toList(growable: false);
  }

  IconData _permissionIcon(_PermissionItem item) {
    return switch (item) {
      _PermissionItem.microphone => Icons.mic_none_rounded,
      _PermissionItem.notifications => Icons.notifications_none_rounded,
      _PermissionItem.exactAlarm => Icons.alarm_rounded,
      _PermissionItem.location => Icons.location_on_outlined,
      _PermissionItem.autoStart => Icons.restart_alt_rounded,
      _PermissionItem.batteryUnrestricted =>
        Icons.battery_charging_full_rounded,
    };
  }

  String _permissionLabel(_PermissionItem item) {
    return switch (item) {
      _PermissionItem.microphone => _localized(zh: '麦克风', en: 'Microphone'),
      _PermissionItem.notifications =>
        _localized(zh: '通知', en: 'Notifications'),
      _PermissionItem.exactAlarm =>
        _localized(zh: '闹铃（精准提醒）', en: 'Exact alarm'),
      _PermissionItem.location => _localized(zh: '定位', en: 'Location'),
      _PermissionItem.autoStart => _localized(zh: '自启动', en: 'Auto-start'),
      _PermissionItem.batteryUnrestricted =>
        _localized(zh: '省电无限制', en: 'Battery unrestricted'),
    };
  }

  String _permissionReason(_PermissionItem item) {
    return switch (item) {
      _PermissionItem.microphone => _localized(
          zh: '用于录音并发送语音消息。',
          en: 'Needed to record and send voice messages.',
        ),
      _PermissionItem.notifications => _localized(
          zh: '用于接收待办复习与同步提醒。',
          en: 'Needed for reminder and sync notifications.',
        ),
      _PermissionItem.exactAlarm => _localized(
          zh: '用于按时触发提醒，避免被系统延迟。',
          en: 'Keeps reminder delivery on time.',
        ),
      _PermissionItem.location => _localized(
          zh: '用于拍照时写入地理位置信息。',
          en: 'Adds location metadata when taking photos.',
        ),
      _PermissionItem.autoStart => _localized(
          zh: '用于重启后自动恢复提醒与后台任务。',
          en: 'Restarts reminders/background tasks after reboot.',
        ),
      _PermissionItem.batteryUnrestricted => _localized(
          zh: '用于减少省电策略导致的后台中断。',
          en: 'Reduces background interruptions by battery saver.',
        ),
    };
  }

  String _permissionUnavailableHint() {
    return _localized(
      zh: '当前平台暂不提供系统权限快捷跳转，请手动在系统设置中检查。',
      en: 'This platform has no direct permission shortcut. Please review settings manually.',
    );
  }

  Future<void> _openPermissionSettings(_PermissionItem item) async {
    if (widget.uriLauncher == null) {
      final openedByNative =
          await _openPermissionSettingsViaPlatformChannel(item);
      if (openedByNative) {
        return;
      }
    }

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

  Future<bool> _openPermissionSettingsViaPlatformChannel(
    _PermissionItem item,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final opened = await _kPermissionChannel.invokeMethod<bool>(
        'openPermissionSettings',
        <String, Object?>{'item': item.channelValue},
      );
      return opened == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
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
      _PermissionItem.notifications => <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.notifications',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ],
      _PermissionItem.location => <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ],
      _PermissionItem.autoStart => <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.LoginItems-Settings.extension',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ],
      _PermissionItem.exactAlarm => <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.notifications',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ],
      _PermissionItem.batteryUnrestricted => <Uri>[
          Uri.parse('x-apple.systempreferences:com.apple.preference.battery'),
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
      _PermissionItem.notifications => <Uri>[
          Uri.parse('ms-settings:notifications'),
          Uri.parse('ms-settings:quiethours'),
        ],
      _PermissionItem.exactAlarm => <Uri>[
          Uri.parse('ms-settings:notifications'),
          Uri.parse('ms-settings:quiethours'),
        ],
      _PermissionItem.location => <Uri>[
          Uri.parse('ms-settings:privacy-location'),
        ],
      _PermissionItem.autoStart => <Uri>[
          Uri.parse('ms-settings:startupapps'),
          Uri.parse('ms-settings:appsfeatures'),
        ],
      _PermissionItem.batteryUnrestricted => <Uri>[
          Uri.parse('ms-settings:batterysaver'),
          Uri.parse('ms-settings:batterysaver-settings'),
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.welcomeGuide;
    final permissionTiles = _permissionTiles();
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
                            if (permissionTiles.isEmpty)
                              Text(
                                _permissionUnavailableHint(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            for (var i = 0;
                                i < permissionTiles.length;
                                i++) ...[
                              _PermissionTile(
                                tileKey: permissionTiles[i].key,
                                icon: permissionTiles[i].icon,
                                label: permissionTiles[i].label,
                                reason: permissionTiles[i].reason,
                                onTap: () => unawaited(
                                  _openPermissionSettings(
                                      permissionTiles[i].item),
                                ),
                              ),
                              if (i != permissionTiles.length - 1)
                                const SizedBox(height: 8),
                            ],
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
    required this.reason,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String label;
  final String reason;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 2),
                  Text(
                    reason,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
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
  notifications,
  exactAlarm,
  location,
  autoStart,
  batteryUnrestricted,
}

extension on _PermissionItem {
  String get channelValue {
    return switch (this) {
      _PermissionItem.microphone => 'microphone',
      _PermissionItem.notifications => 'notifications',
      _PermissionItem.exactAlarm => 'exact_alarm',
      _PermissionItem.location => 'location',
      _PermissionItem.autoStart => 'auto_start',
      _PermissionItem.batteryUnrestricted => 'battery_unrestricted',
    };
  }

  String get keySuffix {
    return switch (this) {
      _PermissionItem.microphone => 'microphone',
      _PermissionItem.notifications => 'notifications',
      _PermissionItem.exactAlarm => 'exact_alarm',
      _PermissionItem.location => 'location',
      _PermissionItem.autoStart => 'auto_start',
      _PermissionItem.batteryUnrestricted => 'battery',
    };
  }
}

class _PermissionTileData {
  const _PermissionTileData({
    required this.item,
    required this.key,
    required this.icon,
    required this.label,
    required this.reason,
  });

  final _PermissionItem item;
  final Key key;
  final IconData icon;
  final String label;
  final String reason;
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_shell_style.dart';
import '../../app/theme.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../features/settings/cloud_account_page.dart';
import '../../features/settings/self_managed_setup_page.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'welcome_status.dart';

part 'welcome_page_widgets.dart';

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

class _WelcomePageState extends State<WelcomePage> with WidgetsBindingObserver {
  static const _kPermissionLaunchFailedKey =
      ValueKey('welcome_guide_permission_launch_failed');
  static const _kPermissionChannel = MethodChannel('secondloop/permissions');

  bool _statusLoaded = false;
  bool _permissionStatusLoaded = false;
  int _permissionStatusGeneration = 0;
  WelcomeGuideStatus _status = const WelcomeGuideStatus(
    runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
  );
  _WelcomeGuideStep _step = _WelcomeGuideStep.runtime;
  Map<_PermissionItem, _PermissionStatus> _permissionStatusMap =
      const <_PermissionItem, _PermissionStatus>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_reloadPermissionStatuses());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_statusLoaded) {
      _statusLoaded = true;
      unawaited(_reloadStatus());
    }
    if (_permissionStatusLoaded) return;
    _permissionStatusLoaded = true;
    unawaited(_reloadPermissionStatuses());
  }

  Future<void> _reloadStatus() async {
    WelcomeGuideStatus status;
    try {
      status = await widget.statusLoader(context);
    } catch (_) {
      status = const WelcomeGuideStatus(
        runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
      );
    }

    if (!mounted) return;
    setState(() {
      _status = status;
      _step = _runtimeReady(status)
          ? _WelcomeGuideStep.permissions
          : _WelcomeGuideStep.runtime;
    });
  }

  bool _runtimeReady(WelcomeGuideStatus status) {
    return status.runtimeMode != WelcomeGuideRuntimeMode.notConfigured;
  }

  Future<void> _openManagedProSetup(BuildContext launchContext) async {
    await pushPageWithInheritedScopes<void>(
      Navigator.of(launchContext),
      launchContext,
      CloudAccountPage(
        entryMode: CloudAccountEntryMode.onboarding,
        onEntitled: () {
          final navigator = Navigator.of(launchContext);
          if (navigator.canPop()) navigator.pop();
          widget.onFinishSetup();
        },
      ),
    );
    if (!mounted) return;
    await _reloadStatus();
  }

  Future<void> _openSelfManagedSetup(BuildContext launchContext) async {
    await pushPageWithInheritedScopes<void>(
      Navigator.of(launchContext),
      launchContext,
      const SelfManagedSetupPage(),
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

  List<_PermissionItem> _permissionItems() {
    if (kIsWeb) {
      return const <_PermissionItem>[];
    }

    return switch (defaultTargetPlatform) {
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
  }

  List<_PermissionTileData> _permissionTiles() {
    return _permissionItems()
        .map(
          (item) => _PermissionTileData(
            item: item,
            key: ValueKey('welcome_guide_permission_${item.keySuffix}'),
            icon: _permissionIcon(item),
            label: _permissionLabel(item),
            reason: _permissionReason(item),
            status: _permissionStatusMap[item] ?? _PermissionStatus.unknown,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _reloadPermissionStatuses() async {
    final items = _permissionItems();
    final generation = ++_permissionStatusGeneration;
    final resolved = <_PermissionItem, _PermissionStatus>{};
    for (final item in items) {
      resolved[item] = await _resolvePermissionStatus(item);
    }
    if (!mounted || generation != _permissionStatusGeneration) return;
    setState(() => _permissionStatusMap = resolved);
  }

  Future<_PermissionStatus> _resolvePermissionStatus(
    _PermissionItem item,
  ) async {
    if (kIsWeb) return _PermissionStatus.unknown;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _resolveAndroidPermissionStatus(item);
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return _PermissionStatus.unknown;
    }
  }

  Future<_PermissionStatus> _resolveAndroidPermissionStatus(
    _PermissionItem item,
  ) async {
    try {
      final status = await _kPermissionChannel.invokeMethod<String>(
        'queryPermissionStatus',
        <String, Object?>{'item': item.channelValue},
      );
      return _permissionStatusFromChannelValue(status);
    } on MissingPluginException {
      return _PermissionStatus.unknown;
    } on PlatformException {
      return _PermissionStatus.unknown;
    } catch (_) {
      return _PermissionStatus.unknown;
    }
  }

  String _permissionStatusLabel(_PermissionStatus status) {
    return switch (status) {
      _PermissionStatus.enabled => _localized(zh: '已开启', en: 'Enabled'),
      _PermissionStatus.disabled => _localized(zh: '未开启', en: 'Disabled'),
      _PermissionStatus.unknown => _localized(zh: '无法检测', en: 'Unknown'),
    };
  }

  String _permissionSummaryStatusLabel() {
    final statuses = _permissionTiles()
        .map((tile) => tile.status)
        .where((status) => status != _PermissionStatus.unknown)
        .toList(growable: false);
    if (statuses.isNotEmpty &&
        statuses.every((status) => status == _PermissionStatus.enabled)) {
      return _localized(zh: '已开启', en: 'Enabled');
    }
    return context.t.welcomeGuide.permissions.statusNeedsReview;
  }

  _PermissionStatus _permissionStatusFromChannelValue(String? value) {
    return switch (value) {
      'enabled' => _PermissionStatus.enabled,
      'disabled' => _PermissionStatus.disabled,
      _ => _PermissionStatus.unknown,
    };
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
    return context.t.welcomeGuide.permissions.openFailed;
  }

  Future<void> _openPermissionSettings(_PermissionItem item) async {
    if (widget.uriLauncher == null) {
      final openedByNative =
          await _openPermissionSettingsViaPlatformChannel(item);
      if (openedByNative) {
        unawaited(_reloadPermissionStatuses());
        return;
      }
    }

    for (final uri in _permissionSettingsUris(item)) {
      try {
        final launched = await _launch(uri);
        if (launched) {
          unawaited(_reloadPermissionStatuses());
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
    return Theme(
      data: _welcomeTheme(context),
      child: Builder(
        builder: _buildContent,
      ),
    );
  }

  ThemeData _welcomeTheme(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final platform = theme.platform;
    if (theme.brightness == Brightness.dark) {
      return AppTheme.dark(locale: locale, platform: platform);
    }
    return AppTheme.light(locale: locale, platform: platform);
  }

  Widget _buildContent(BuildContext context) {
    final t = context.t.welcomeGuide;
    final colors = _WelcomeShellColors.of(context);
    final managedProReady =
        _status.runtimeMode == WelcomeGuideRuntimeMode.managedPro;
    final selfManagedReady =
        _status.runtimeMode == WelcomeGuideRuntimeMode.selfManaged;
    final permissionTiles = _permissionTiles();
    final permissionSummaryStatusLabel = _permissionSummaryStatusLabel();
    final permissionSummaryStatusKey = ValueKey(
      permissionSummaryStatusLabel == t.permissions.statusNeedsReview
          ? 'welcome_guide_permissions_status_needs_review'
          : 'welcome_guide_permissions_status_enabled',
    );
    final showPermissionsStep = _step == _WelcomeGuideStep.permissions;
    final contentChildren = showPermissionsStep
        ? <Widget>[
            _PermissionPanel(
              title: t.permissions.title,
              description: t.permissions.description,
              statusLabel: permissionSummaryStatusLabel,
              statusKey: permissionSummaryStatusKey,
              unavailableHint: _permissionUnavailableHint(),
              permissionTiles: permissionTiles,
              statusLabelFor: _permissionStatusLabel,
              onPermissionTap: (item) =>
                  unawaited(_openPermissionSettings(item)),
            ),
          ]
        : <Widget>[
            _WelcomeModeCards(
              managedCard: _WelcomeGuideCard(
                cardKey: const ValueKey('welcome_guide_card_managed_pro'),
                icon: Icons.cloud_done_rounded,
                title: t.runtime.managedPro.title,
                description: t.runtime.managedPro.description,
                comparisonTitle: t.runtime.managedPro.comparisonTitle,
                comparisonItems: [
                  t.runtime.managedPro.comparison.cloudflare,
                  t.runtime.managedPro.comparison.workersPaid,
                  t.runtime.managedPro.comparison.providerKeys,
                  t.runtime.managedPro.comparison.maintenance,
                ],
                comparisonKey:
                    const ValueKey('welcome_guide_managed_pro_comparison'),
                comparisonPositive: true,
                statusLabel: managedProReady
                    ? t.runtime.statusReady
                    : t.runtime.statusNotSet,
                statusKey: ValueKey(
                  managedProReady
                      ? 'welcome_guide_managed_pro_status_ready'
                      : 'welcome_guide_managed_pro_status_not_set',
                ),
                ready: managedProReady,
                actionKey:
                    const ValueKey('welcome_guide_card_managed_pro_open'),
                actionLabel: t.runtime.managedPro.open,
                onActionTap: () => unawaited(_openManagedProSetup(context)),
              ),
              selfManagedCard: _WelcomeGuideCard(
                cardKey: const ValueKey('welcome_guide_card_self_managed'),
                icon: Icons.dns_rounded,
                title: t.runtime.selfManaged.title,
                description: t.runtime.selfManaged.description,
                comparisonTitle: t.runtime.selfManaged.comparisonTitle,
                comparisonItems: [
                  t.runtime.selfManaged.comparison.cloudflare,
                  t.runtime.selfManaged.comparison.workersPaid,
                  t.runtime.selfManaged.comparison.providerKeys,
                  t.runtime.selfManaged.comparison.maintenance,
                ],
                comparisonKey:
                    const ValueKey('welcome_guide_self_managed_comparison'),
                comparisonPositive: false,
                statusLabel: selfManagedReady
                    ? t.runtime.statusReady
                    : t.runtime.statusNotSet,
                statusKey: ValueKey(
                  selfManagedReady
                      ? 'welcome_guide_self_managed_status_ready'
                      : 'welcome_guide_self_managed_status_not_set',
                ),
                ready: selfManagedReady,
                actionKey:
                    const ValueKey('welcome_guide_card_self_managed_open'),
                actionLabel: t.runtime.selfManaged.open,
                onActionTap: () => unawaited(_openSelfManagedSetup(context)),
              ),
            ),
          ];

    return Scaffold(
      key: const ValueKey('welcome_guide_page'),
      backgroundColor: colors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pane = _WelcomeContentPane(
            footer: showPermissionsStep
                ? _WelcomeFooter(
                    skipLabel: t.actions.skip,
                    finishLabel: t.actions.finish,
                    onSkip: widget.onSkipForNow,
                    onFinish: widget.onFinishSetup,
                  )
                : null,
            children: [
              Text(
                t.title,
                key: const ValueKey('welcome_guide_header_title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.text,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AgentDesignTokens.gapSm),
              Text(
                t.subtitle,
                key: const ValueKey('welcome_guide_header_subtitle'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.muted,
                    ),
              ),
              const SizedBox(height: AgentDesignTokens.gapXl),
              ...contentChildren,
            ],
          );

          return Padding(
            padding: const EdgeInsets.all(AppShellStyle.desktopShellMargin),
            child: SlSurface(
              key: const ValueKey('welcome_guide_workspace'),
              color: colors.surface,
              borderColor: colors.border,
              borderRadius: BorderRadius.circular(
                AppShellStyle.desktopShellRadius,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  AppShellStyle.desktopShellRadius,
                ),
                child: pane,
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _WelcomeGuideStep {
  runtime,
  permissions,
}

enum _PermissionItem {
  microphone,
  notifications,
  exactAlarm,
  location,
  autoStart,
  batteryUnrestricted,
}

enum _PermissionStatus {
  enabled,
  disabled,
  unknown,
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

extension on _PermissionStatus {
  String get keySuffix {
    return switch (this) {
      _PermissionStatus.enabled => 'enabled',
      _PermissionStatus.disabled => 'disabled',
      _PermissionStatus.unknown => 'unknown',
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
    required this.status,
  });

  final _PermissionItem item;
  final Key key;
  final IconData icon;
  final String label;
  final String reason;
  final _PermissionStatus status;
}

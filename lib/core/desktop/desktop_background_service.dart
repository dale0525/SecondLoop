import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:universal_io/io.dart';
import 'package:window_manager/window_manager.dart';

import '../../i18n/strings.g.dart';
import '../ai/ai_routing.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../cloud/cloud_usage_client.dart';
import '../cloud/vault_usage_client.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_config_store.dart';
import 'desktop_boot_prefs.dart';
import 'desktop_launch_args.dart';
import 'desktop_tray_icon_config.dart';
import 'desktop_tray_click_controller.dart';
import 'desktop_tray_menu_controller.dart'
    show
        DesktopTrayMenuController,
        DesktopTrayMenuLabels,
        DesktopTrayMenuState,
        DesktopTrayProUsage;
import 'desktop_window_display_controller.dart';

class DesktopBackgroundService extends StatefulWidget {
  const DesktopBackgroundService({
    required this.child,
    required this.onOpenSettingsRequested,
    this.silentStartupRequested = false,
    super.key,
  });

  final Widget child;
  final Future<void> Function() onOpenSettingsRequested;
  final bool silentStartupRequested;

  @override
  State<DesktopBackgroundService> createState() =>
      _DesktopBackgroundServiceState();
}

class _DesktopBackgroundServiceState extends State<DesktopBackgroundService>
    with WindowListener, TrayListener {
  bool _enabled = false;
  bool _quitting = false;

  DesktopBootConfig _config = DesktopBootConfig.defaults;
  VoidCallback? _bootPrefsListener;

  _LaunchSetup? _launchSetup;

  CloudAuthController? _cloudAuthController;
  Listenable? _cloudAuthListenable;

  SubscriptionStatusController? _subscriptionController;
  SubscriptionStatus _subscriptionStatus = SubscriptionStatus.unknown;

  String _gatewayBaseUrl = '';

  final CloudUsageClient _cloudUsageClient = CloudUsageClient();
  final VaultUsageClient _vaultUsageClient = VaultUsageClient();
  final SyncConfigStore _syncConfigStore = SyncConfigStore();

  DesktopTrayProUsage? _trayProUsage;
  bool _refreshingProUsage = false;
  DateTime? _lastProUsageRefreshAt;

  late final DesktopTrayMenuController _trayMenuController =
      DesktopTrayMenuController(
    onOpenWindow: _openMainWindowFromTrayIcon,
    onOpenSettings: _openSettingsFromTrayMenu,
    onToggleStartWithSystem: _toggleStartWithSystemFromTrayMenu,
    onQuit: _quitFromTrayMenu,
  );

  late final DesktopTrayClickController _trayClickController =
      DesktopTrayClickController(
    onLeftClick: _openMainWindowFromTrayIcon,
    onRightClick: _showTrayMenu,
  );

  final DesktopWindowDisplayController _windowDisplayController =
      DesktopWindowDisplayController(
    adapter: _WindowManagerDisplayAdapter(windowManager),
  );

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  bool get _isWidgetTestEnvironment {
    if (kIsWeb) return false;
    return Platform.environment.containsKey('FLUTTER_TEST');
  }

  bool get _isSignedInProAccount {
    final uid = _cloudAuthController?.uid?.trim() ?? '';
    if (uid.isEmpty) return false;
    return _subscriptionStatus == SubscriptionStatus.entitled;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isDesktop || _isWidgetTestEnvironment) {
      return;
    }

    final cloudScope = CloudAuthScope.maybeOf(context);
    _gatewayBaseUrl = cloudScope?.gatewayConfig.baseUrl.trim() ?? '';
    _bindCloudAuth(cloudScope?.controller);
    _bindSubscription(SubscriptionScope.maybeOf(context));

    if (_enabled) {
      return;
    }

    _enabled = true;
    unawaited(_initDesktopServices());
  }

  void _bindCloudAuth(CloudAuthController? controller) {
    if (identical(_cloudAuthController, controller)) {
      return;
    }

    _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
    _cloudAuthController = controller;

    final listenable =
        controller is Listenable ? controller as Listenable : null;
    _cloudAuthListenable = listenable;
    listenable?.addListener(_onCloudAuthChanged);

    unawaited(_refreshProUsage(force: true));
  }

  void _bindSubscription(SubscriptionStatusController? controller) {
    if (identical(_subscriptionController, controller)) {
      return;
    }

    _subscriptionController?.removeListener(_onSubscriptionChanged);
    _subscriptionController = controller;
    _subscriptionStatus = controller?.status ?? SubscriptionStatus.unknown;
    controller?.addListener(_onSubscriptionChanged);

    unawaited(_refreshProUsage(force: true));
  }

  Future<void> _initDesktopServices() async {
    await _runSafely(() async {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      trayManager.addListener(this);

      await DesktopBootPrefs.load();
      _config = DesktopBootPrefs.value.value;
      _bootPrefsListener = _onBootPrefsChanged;
      DesktopBootPrefs.value.addListener(_onBootPrefsChanged);

      await _loadLaunchSetup();
      await _applyBootConfig(previous: null);
      await _setupTray();
      await _syncTrayMenu();
      unawaited(_refreshProUsage(force: true));
      await _applySilentStartupIfRequested();
    });
  }

  Future<void> _loadLaunchSetup() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final appName = packageInfo.appName.trim().isNotEmpty
        ? packageInfo.appName.trim()
        : 'SecondLoop';
    final packageName = packageInfo.packageName.trim().isEmpty
        ? null
        : packageInfo.packageName.trim();

    _launchSetup = _LaunchSetup(
      appName: appName,
      appPath: Platform.resolvedExecutable,
      packageName: packageName,
    );
  }

  void _onBootPrefsChanged() {
    final next = DesktopBootPrefs.value.value;
    if (next == _config) {
      return;
    }

    final previous = _config;
    _config = next;
    unawaited(_runSafely(() async {
      await _applyBootConfig(previous: previous);
      await _syncTrayMenu();
    }));
  }

  void _onCloudAuthChanged() {
    unawaited(_refreshProUsage(force: true));
  }

  void _onSubscriptionChanged() {
    final controller = _subscriptionController;
    final next = controller?.status ?? SubscriptionStatus.unknown;
    if (next == _subscriptionStatus) {
      return;
    }

    _subscriptionStatus = next;
    unawaited(_refreshProUsage(force: true));
  }

  Future<void> _applyBootConfig({DesktopBootConfig? previous}) async {
    await windowManager.setPreventClose(_config.keepRunningInBackground);

    final launchSetup = _launchSetup;
    if (launchSetup == null) {
      return;
    }

    launchAtStartup.setup(
      appName: launchSetup.appName,
      appPath: launchSetup.appPath,
      packageName: launchSetup.packageName,
      args: _config.silentStartup
          ? const <String>[kDesktopSilentStartupArg]
          : const <String>[],
    );

    final isEnabled = await launchAtStartup.isEnabled();
    if (_config.startWithSystem) {
      if (isEnabled &&
          previous != null &&
          previous.silentStartup != _config.silentStartup) {
        await launchAtStartup.disable();
        await launchAtStartup.enable();
        return;
      }
      if (!isEnabled) {
        await launchAtStartup.enable();
      }
      return;
    }

    if (isEnabled) {
      await launchAtStartup.disable();
    }
  }

  Future<void> _setupTray() async {
    final iconConfig = trayIconConfigForPlatform(defaultTargetPlatform);

    await trayManager.setIcon(
      iconConfig.assetPath,
      isTemplate: iconConfig.isTemplate,
    );
    await trayManager.setToolTip('SecondLoop');
  }

  DesktopTrayMenuLabels _trayMenuLabels() {
    return DesktopTrayMenuLabels(
      open: context.t.common.actions.open,
      settings: context.t.settings.title,
      startWithSystem: context.t.settings.desktopBoot.startWithSystem.title,
      quit: context.t.settings.desktopTray.menu.quit,
      signedIn: context.t.settings.desktopTray.pro.signedIn,
      aiUsage: context.t.settings.desktopTray.pro.aiUsage,
      storageUsage: context.t.settings.desktopTray.pro.storageUsage,
    );
  }

  Future<void> _syncTrayMenu() async {
    if (!_enabled || !mounted) {
      return;
    }

    final menu = _trayMenuController.buildMenu(
      labels: _trayMenuLabels(),
      state: DesktopTrayMenuState(
        startWithSystemEnabled: _config.startWithSystem,
        proUsage: _trayProUsage,
      ),
    );

    await trayManager.setContextMenu(menu);
  }

  Future<void> _showTrayMenu() async {
    await _syncTrayMenu();
    await trayManager.popUpContextMenu();
    unawaited(_refreshProUsage(force: true));
  }

  Future<void> _applySilentStartupIfRequested() async {
    if (!widget.silentStartupRequested || !_config.silentStartup) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    await _windowDisplayController.hideToTray();
  }

  Future<void> _refreshProUsage({bool force = false}) async {
    if (!_enabled) {
      return;
    }

    if (!_isSignedInProAccount) {
      if (_trayProUsage != null) {
        _trayProUsage = null;
        await _syncTrayMenu();
      }
      return;
    }

    if (_refreshingProUsage) {
      return;
    }

    final now = DateTime.now();
    final last = _lastProUsageRefreshAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(minutes: 2)) {
      return;
    }

    _refreshingProUsage = true;
    _lastProUsageRefreshAt = now;

    try {
      final usage = await _fetchProUsage();
      if (usage == _trayProUsage) {
        return;
      }

      _trayProUsage = usage;
      await _syncTrayMenu();
    } finally {
      _refreshingProUsage = false;
    }
  }

  Future<DesktopTrayProUsage?> _fetchProUsage() async {
    final controller = _cloudAuthController;
    if (controller == null) {
      return null;
    }

    final uid = controller.uid?.trim() ?? '';
    if (uid.isEmpty) {
      return null;
    }

    String email = controller.email?.trim() ?? '';
    if (email.isEmpty) {
      try {
        await controller.refreshUserInfo();
        email = controller.email?.trim() ?? '';
      } catch (_) {
        email = '';
      }
    }
    if (email.isEmpty) {
      email = uid;
    }

    String? idToken;
    try {
      idToken = await controller.getIdToken();
    } catch (_) {
      idToken = null;
    }

    final trimmedToken = idToken?.trim() ?? '';
    if (trimmedToken.isEmpty) {
      return DesktopTrayProUsage(
        email: email,
        aiUsagePercent: null,
        storageUsagePercent: null,
      );
    }

    int? aiUsagePercent;
    if (_gatewayBaseUrl.isNotEmpty) {
      try {
        final summary = await _cloudUsageClient.fetchUsageSummary(
          cloudGatewayBaseUrl: _gatewayBaseUrl,
          idToken: trimmedToken,
        );
        aiUsagePercent = summary.askAiUsagePercent;
      } catch (_) {
        aiUsagePercent = null;
      }
    }

    int? storageUsagePercent;
    final managedVaultBaseUrl =
        (await _syncConfigStore.resolveManagedVaultBaseUrl())?.trim() ?? '';
    if (managedVaultBaseUrl.isNotEmpty) {
      try {
        final summary = await _vaultUsageClient.fetchVaultUsageSummary(
          managedVaultBaseUrl: managedVaultBaseUrl,
          vaultId: uid,
          idToken: trimmedToken,
        );

        final limitBytes = summary.limitBytes;
        if (limitBytes != null && limitBytes > 0) {
          final ratio = summary.totalBytesUsed / limitBytes;
          storageUsagePercent = (ratio * 100).round().clamp(0, 100);
        }
      } catch (_) {
        storageUsagePercent = null;
      }
    }

    return DesktopTrayProUsage(
      email: email,
      aiUsagePercent: aiUsagePercent,
      storageUsagePercent: storageUsagePercent,
    );
  }

  @override
  void onWindowClose() {
    if (_quitting || !_enabled) {
      return;
    }

    if (_config.keepRunningInBackground) {
      unawaited(_runSafely(_windowDisplayController.hideToTray));
      return;
    }

    unawaited(_quitApp());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_runSafely(_trayClickController.handleLeftMouseDown));
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_runSafely(_trayClickController.handleRightMouseDown));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    unawaited(
      _runSafely(
        () => _trayMenuController.onMenuItemClick(
          menuItem,
          startWithSystemEnabled: _config.startWithSystem,
        ),
      ),
    );
  }

  Future<void> _openMainWindowFromTrayIcon() async {
    await _showWindow();
  }

  Future<void> _openSettingsFromTrayMenu() async {
    await _showWindow();
    await widget.onOpenSettingsRequested();
  }

  Future<void> _toggleStartWithSystemFromTrayMenu(bool enabled) async {
    await DesktopBootPrefs.setStartWithSystem(enabled);
  }

  Future<void> _quitFromTrayMenu() async {
    await _quitApp();
  }

  Future<void> _showWindow() async {
    await _windowDisplayController.showMainWindow();
  }

  Future<void> _quitApp() async {
    if (_quitting) {
      return;
    }

    _quitting = true;
    await _runSafely(() async {
      await windowManager.setPreventClose(false);
      await trayManager.destroy();
      await windowManager.destroy();
    });
  }

  Future<void> _runSafely(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('Desktop background service error: $error');
    }
  }

  @override
  void dispose() {
    final wasEnabled = _enabled;
    _enabled = false;
    _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
    _subscriptionController?.removeListener(_onSubscriptionChanged);

    if (wasEnabled) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);

      final listener = _bootPrefsListener;
      if (listener != null) {
        DesktopBootPrefs.value.removeListener(listener);
      }

      unawaited(_runSafely(() => trayManager.destroy()));
    }

    _cloudUsageClient.dispose();
    _vaultUsageClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

final class _LaunchSetup {
  const _LaunchSetup({
    required this.appName,
    required this.appPath,
    required this.packageName,
  });

  final String appName;
  final String appPath;
  final String? packageName;
}

final class _WindowManagerDisplayAdapter implements WindowDisplayAdapter {
  const _WindowManagerDisplayAdapter(this._windowManager);

  final WindowManager _windowManager;

  @override
  Future<void> focus() => _windowManager.focus();

  @override
  Future<void> hide() => _windowManager.hide();

  @override
  Future<void> setSkipTaskbar(bool skipTaskbar) =>
      _windowManager.setSkipTaskbar(skipTaskbar);

  @override
  Future<void> show() => _windowManager.show();
}

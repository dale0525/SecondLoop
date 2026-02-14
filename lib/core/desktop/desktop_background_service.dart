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
import 'desktop_tray_menu_controller.dart' show DesktopTrayProUsage;
import 'desktop_tray_popup_layout.dart';
import 'desktop_tray_popup_window.dart';

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

  bool _trayPopupVisible = false;
  bool _windowWasVisibleBeforeTrayPopup = false;
  _SavedWindowState? _savedWindowState;

  Timer? _leftTrayMenuTimer;
  DateTime? _lastLeftTrayClickAt;

  static const Duration _trayDoubleClickThreshold = Duration(milliseconds: 220);
  static const double _trayPopupVerticalGap = 8;

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

  bool get _reserveProUsageSpaceInTrayPopup =>
      _isSignedInProAccount || _trayProUsage != null;

  Size get _trayPopupWindowSize => resolveTrayPopupWindowSize(
        reserveProUsageSpace: _reserveProUsageSpaceInTrayPopup,
      );

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
      if (_trayPopupVisible && mounted) {
        setState(() {});
      }
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

  Future<void> _applySilentStartupIfRequested() async {
    if (!widget.silentStartupRequested || !_config.silentStartup) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    await windowManager.hide();
  }

  Future<void> _refreshProUsage({bool force = false}) async {
    if (!_enabled) {
      return;
    }

    if (!_isSignedInProAccount) {
      if (_trayProUsage != null) {
        _trayProUsage = null;
        if (_trayPopupVisible && mounted) {
          setState(() {});
        }
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
      if (_trayPopupVisible && mounted) {
        setState(() {});
      }
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

    if (_trayPopupVisible) {
      unawaited(
        _runSafely(
          () => _dismissTrayPopup(keepWindowVisible: false),
        ),
      );
      return;
    }

    if (_config.keepRunningInBackground) {
      unawaited(_runSafely(() => windowManager.hide()));
      return;
    }

    unawaited(_quitApp());
  }

  @override
  void onWindowBlur() {
    if (!_trayPopupVisible) {
      return;
    }

    unawaited(
      _runSafely(
        () => _dismissTrayPopup(keepWindowVisible: false),
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    final now = DateTime.now();
    final last = _lastLeftTrayClickAt;

    if (last != null && now.difference(last) <= _trayDoubleClickThreshold) {
      _cancelPendingLeftTrayMenu();
      _lastLeftTrayClickAt = null;
      unawaited(_runSafely(_openMainWindowFromTrayIcon));
      return;
    }

    _lastLeftTrayClickAt = now;
    _cancelPendingLeftTrayMenu();
    _leftTrayMenuTimer = Timer(_trayDoubleClickThreshold, () {
      _leftTrayMenuTimer = null;
      _lastLeftTrayClickAt = null;
      unawaited(_runSafely(_showTrayPopup));
    });
  }

  @override
  void onTrayIconRightMouseDown() {
    _cancelPendingLeftTrayMenu();
    _lastLeftTrayClickAt = null;
    unawaited(_runSafely(_showTrayPopup));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {}

  void _cancelPendingLeftTrayMenu() {
    _leftTrayMenuTimer?.cancel();
    _leftTrayMenuTimer = null;
  }

  Future<void> _showTrayPopup() async {
    if (_trayPopupVisible) {
      await _dismissTrayPopup(keepWindowVisible: false);
      return;
    }

    await _enterTrayPopupMode();
    unawaited(_refreshProUsage(force: true));
  }

  Future<void> _enterTrayPopupMode() async {
    if (_trayPopupVisible) {
      return;
    }

    _savedWindowState = await _captureWindowState();
    _windowWasVisibleBeforeTrayPopup = await windowManager.isVisible();

    await windowManager.setAlwaysOnTop(true);
    await windowManager.setResizable(false);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    final popupSize = _trayPopupWindowSize;
    await windowManager.setSize(popupSize);
    final popupPosition = await _resolveTrayPopupPosition();
    await windowManager.setPosition(popupPosition);
    await windowManager.show();
    await windowManager.focus();

    if (!mounted) {
      return;
    }

    setState(() {
      _trayPopupVisible = true;
    });
  }

  Future<void> _dismissTrayPopup({required bool keepWindowVisible}) async {
    if (!_trayPopupVisible && _savedWindowState == null) {
      return;
    }

    final savedWindowState = _savedWindowState;
    final wasVisible = _windowWasVisibleBeforeTrayPopup;

    _savedWindowState = null;
    _windowWasVisibleBeforeTrayPopup = false;

    if (_trayPopupVisible && mounted) {
      setState(() {
        _trayPopupVisible = false;
      });
    }

    if (savedWindowState != null) {
      await _restoreWindowState(savedWindowState);
    }

    final shouldShowWindow = keepWindowVisible || wasVisible;
    if (shouldShowWindow) {
      await windowManager.show();
      await windowManager.focus();
      return;
    }

    await windowManager.hide();
  }

  Future<_SavedWindowState> _captureWindowState() async {
    final bounds = await windowManager.getBounds();
    final resizable = await windowManager.isResizable();
    final alwaysOnTop = await windowManager.isAlwaysOnTop();
    final skipTaskbar = await windowManager.isSkipTaskbar();

    return _SavedWindowState(
      bounds: bounds,
      resizable: resizable,
      alwaysOnTop: alwaysOnTop,
      skipTaskbar: skipTaskbar,
    );
  }

  Future<void> _restoreWindowState(_SavedWindowState state) async {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );
    await windowManager.setResizable(state.resizable);
    await windowManager.setAlwaysOnTop(state.alwaysOnTop);
    await windowManager.setSkipTaskbar(state.skipTaskbar);
    await windowManager.setBounds(state.bounds);
  }

  Future<Offset> _resolveTrayPopupPosition() async {
    final trayBounds = await trayManager.getBounds();
    if (trayBounds == null) {
      final currentBounds = await windowManager.getBounds();
      return currentBounds.topLeft;
    }

    final popupSize = _trayPopupWindowSize;
    final x = (trayBounds.center.dx - (popupSize.width / 2))
        .clamp(0.0, double.infinity)
        .toDouble();
    final y = (trayBounds.bottom + _trayPopupVerticalGap)
        .clamp(0.0, double.infinity)
        .toDouble();

    return Offset(x, y);
  }

  Future<void> _openMainWindowFromTrayIcon() async {
    if (_trayPopupVisible || _savedWindowState != null) {
      await _dismissTrayPopup(keepWindowVisible: true);
      return;
    }

    await _showWindow();
  }

  Future<void> _openSettingsFromTrayPopup() async {
    if (_trayPopupVisible || _savedWindowState != null) {
      await _dismissTrayPopup(keepWindowVisible: true);
    } else {
      await _showWindow();
    }

    await widget.onOpenSettingsRequested();
  }

  Future<void> _toggleStartWithSystemFromTrayPopup(bool enabled) async {
    await DesktopBootPrefs.setStartWithSystem(enabled);
  }

  Future<void> _quitFromTrayPopup() async {
    if (_trayPopupVisible || _savedWindowState != null) {
      await _dismissTrayPopup(keepWindowVisible: false);
    }

    await _quitApp();
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quitApp() async {
    if (_quitting) {
      return;
    }

    _quitting = true;
    _cancelPendingLeftTrayMenu();
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
    _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
    _subscriptionController?.removeListener(_onSubscriptionChanged);

    _cancelPendingLeftTrayMenu();

    if (_enabled) {
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
    final labels = DesktopTrayPopupLabels(
      title: context.t.app.title,
      open: context.t.common.actions.open,
      settings: context.t.settings.title,
      startWithSystem: context.t.settings.desktopBoot.startWithSystem.title,
      quit: context.t.settings.desktopTray.menu.quit,
      signedIn: context.t.settings.desktopTray.pro.signedIn,
      aiUsage: context.t.settings.desktopTray.pro.aiUsage,
      storageUsage: context.t.settings.desktopTray.pro.storageUsage,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: _trayPopupVisible, child: widget.child),
        if (_trayPopupVisible)
          DesktopTrayPopupWindow(
            labels: labels,
            proUsage: _trayProUsage,
            startWithSystemEnabled: _config.startWithSystem,
            refreshingUsage: _refreshingProUsage,
            onOpenWindow: _openMainWindowFromTrayIcon,
            onOpenSettings: _openSettingsFromTrayPopup,
            onToggleStartWithSystem: _toggleStartWithSystemFromTrayPopup,
            onQuit: _quitFromTrayPopup,
          ),
      ],
    );
  }
}

final class _SavedWindowState {
  const _SavedWindowState({
    required this.bounds,
    required this.resizable,
    required this.alwaysOnTop,
    required this.skipTaskbar,
  });

  final Rect bounds;
  final bool resizable;
  final bool alwaysOnTop;
  final bool skipTaskbar;
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

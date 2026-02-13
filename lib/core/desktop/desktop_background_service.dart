import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:universal_io/io.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_boot_prefs.dart';
import 'desktop_launch_args.dart';

const _kTrayMenuShowKey = 'show';
const _kTrayMenuHideKey = 'hide';
const _kTrayMenuQuitKey = 'quit';

class DesktopBackgroundService extends StatefulWidget {
  const DesktopBackgroundService({
    required this.child,
    this.silentStartupRequested = false,
    super.key,
  });

  final Widget child;
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
  VoidCallback? _prefsListener;

  _LaunchSetup? _launchSetup;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  bool get _isWidgetTestEnvironment {
    if (kIsWeb) return false;
    return Platform.environment.containsKey('FLUTTER_TEST');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_enabled || !_isDesktop || _isWidgetTestEnvironment) {
      return;
    }

    _enabled = true;
    unawaited(_initDesktopServices());
  }

  Future<void> _initDesktopServices() async {
    await _runSafely(() async {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      trayManager.addListener(this);

      await DesktopBootPrefs.load();
      _config = DesktopBootPrefs.value.value;
      _prefsListener = _onBootPrefsChanged;
      DesktopBootPrefs.value.addListener(_onBootPrefsChanged);

      await _loadLaunchSetup();
      await _applyBootConfig(previous: null);
      await _setupTray();
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
    }));
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
    final iconAsset = defaultTargetPlatform == TargetPlatform.windows
        ? 'assets/icon/tray_icon.ico'
        : 'assets/icon/tray_icon.png';

    await trayManager.setIcon(
      iconAsset,
      isTemplate: defaultTargetPlatform == TargetPlatform.macOS,
    );
    await trayManager.setToolTip('SecondLoop');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _kTrayMenuShowKey, label: 'Open'),
          MenuItem(key: _kTrayMenuHideKey, label: 'Hide'),
          MenuItem.separator(),
          MenuItem(key: _kTrayMenuQuitKey, label: 'Quit'),
        ],
      ),
    );
  }

  Future<void> _applySilentStartupIfRequested() async {
    if (!widget.silentStartupRequested || !_config.silentStartup) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    await windowManager.hide();
  }

  @override
  void onWindowClose() {
    if (_quitting || !_enabled) {
      return;
    }

    if (_config.keepRunningInBackground) {
      unawaited(_runSafely(() => windowManager.hide()));
      return;
    }

    unawaited(_quitApp());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_runSafely(_toggleWindowVisibility));
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_runSafely(() => trayManager.popUpContextMenu()));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _kTrayMenuShowKey:
        unawaited(_runSafely(_showWindow));
        break;
      case _kTrayMenuHideKey:
        unawaited(_runSafely(() => windowManager.hide()));
        break;
      case _kTrayMenuQuitKey:
        unawaited(_quitApp());
        break;
    }
  }

  Future<void> _toggleWindowVisibility() async {
    final visible = await windowManager.isVisible();
    if (visible) {
      await windowManager.hide();
      return;
    }

    await _showWindow();
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
    await _runSafely(() async {
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      await windowManager.close();
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
    if (_enabled) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);

      final listener = _prefsListener;
      if (listener != null) {
        DesktopBootPrefs.value.removeListener(listener);
      }

      unawaited(_runSafely(() => trayManager.destroy()));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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

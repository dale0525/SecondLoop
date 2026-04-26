import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app/app.dart';
import '../core/backend/app_backend.dart';
import '../core/desktop/desktop_window_manager_bootstrap.dart';
import '../core/desktop/desktop_launch_args.dart';
import '../core/desktop/windows_velopack_uninstall_cleanup.dart';
import '../core/keyboard/macos_key_event_channel_normalizer.dart';
import '../core/quick_capture/quick_capture_controller.dart';
import '../core/update/app_update_service.dart';
import '../core/sync/background_sync.dart';
import '../i18n/locale_prefs.dart';

Future<void> runPlatformApp(
  List<String> args, {
  Future<void> Function()? initializeDesktopWindowManager,
  Future<void> Function()? startupBootstrapRunner,
  void Function(Widget app)? appRunner,
}) async {
  final launchArgs = DesktopLaunchArgs.fromMainArgs(args);
  if (await handleDesktopHookInvocationAndExit(launchArgs)) {
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  installMacOsKeyEventChannelNormalizer();
  await _runDesktopWindowManagerInitialization(
    initializeDesktopWindowManager ?? _initializeDesktopWindowManagerForStartup,
  );
  unawaited((startupBootstrapRunner ?? runStartupBootstrap)());

  (appRunner ?? runApp)(MyApp(launchArgs: launchArgs));
}

Future<void> _initializeDesktopWindowManagerForStartup() async {
  if (kIsWeb) {
    return;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      await DesktopWindowManagerBootstrap.ensureInitialized();
      return;
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return;
  }
}

Future<void> _runDesktopWindowManagerInitialization(
  Future<void> Function() initializer,
) async {
  try {
    await initializer();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'secondloop.startup',
        context: ErrorDescription(
          'while initializing desktop window manager for startup',
        ),
      ),
    );
  }
}

@visibleForTesting
Future<bool> handleDesktopHookInvocationAndExit(
  DesktopLaunchArgs launchArgs, {
  Future<void> Function()? velopackUninstallCleanup,
  void Function(int code)? exitProcess,
}) async {
  if (!launchArgs.shouldExitBeforeLaunchingApp) {
    return false;
  }

  if (launchArgs.velopackUninstallHookInvocationRequested) {
    try {
      await (velopackUninstallCleanup ??
          cleanCurrentWindowsVelopackUninstallResidue)();
    } on Object {
      // Velopack uninstall hooks must exit cleanly even if best-effort cleanup
      // cannot remove every residual path or registry key.
    }
  }

  final resolvedExitProcess = exitProcess ?? io.exit;
  resolvedExitProcess(0);
  return true;
}

const _kStartupTaskTimeout = Duration(seconds: 5);

Future<void> runStartupBootstrap({
  Future<void> Function()? initializeBackgroundSync,
  Future<void> Function()? refreshBackgroundSyncSchedule,
  Future<void> Function()? initializeLocalePrefs,
  Duration taskTimeout = _kStartupTaskTimeout,
}) async {
  await _runStartupTask(
    name: 'background-sync-init',
    task: initializeBackgroundSync ?? BackgroundSync.init,
    timeout: taskTimeout,
  );
  await _runStartupTask(
    name: 'background-sync-refresh-schedule',
    task: refreshBackgroundSyncSchedule ?? BackgroundSync.refreshSchedule,
    timeout: taskTimeout,
  );
  await _runStartupTask(
    name: 'app-locale-bootstrap',
    task: initializeLocalePrefs ?? AppLocaleBootstrap.ensureInitialized,
    timeout: taskTimeout,
  );
}

Future<void> _runStartupTask({
  required String name,
  required Future<void> Function() task,
  required Duration timeout,
}) async {
  try {
    await task().timeout(timeout);
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'secondloop.startup',
        context: ErrorDescription('while running startup task "$name"'),
        informationCollector: () sync* {
          yield DiagnosticsProperty<String>('task', name);
        },
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.backend,
    this.quickCaptureController,
    this.updateService,
    this.launchArgs = const DesktopLaunchArgs(),
  });

  final AppBackend? backend;
  final QuickCaptureController? quickCaptureController;
  final AppUpdateService? updateService;
  final DesktopLaunchArgs launchArgs;

  @override
  Widget build(BuildContext context) => SecondLoopApp(
        backend: backend,
        quickCaptureController: quickCaptureController,
        updateService: updateService,
        launchArgs: launchArgs,
      );
}

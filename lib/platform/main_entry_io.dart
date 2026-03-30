import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app/app.dart';
import '../core/backend/app_backend.dart';
import '../core/desktop/desktop_launch_args.dart';
import '../core/keyboard/macos_key_event_channel_normalizer.dart';
import '../core/quick_capture/quick_capture_controller.dart';
import '../core/update/app_update_service.dart';
import '../core/sync/background_sync.dart';
import '../i18n/locale_prefs.dart';

Future<void> runPlatformApp(List<String> args) async {
  final launchArgs = DesktopLaunchArgs.fromMainArgs(args);
  if (handleDesktopHookInvocationAndExit(launchArgs)) {
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  installMacOsKeyEventChannelNormalizer();
  unawaited(runStartupBootstrap());

  runApp(MyApp(launchArgs: launchArgs));
}

@visibleForTesting
bool handleDesktopHookInvocationAndExit(
  DesktopLaunchArgs launchArgs, {
  void Function(int code)? exitProcess,
}) {
  if (!launchArgs.shouldExitBeforeLaunchingApp) {
    return false;
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

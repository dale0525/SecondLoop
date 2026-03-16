import 'package:flutter/widgets.dart';

import '../core/backend/app_backend.dart';
import '../core/desktop/desktop_launch_args.dart';
import '../core/quick_capture/quick_capture_controller.dart';

Future<void> runPlatformApp(List<String> args) {
  throw UnsupportedError('Unsupported platform');
}

@visibleForTesting
bool handleDesktopHookInvocationAndExit(
  DesktopLaunchArgs launchArgs, {
  void Function(int code)? exitProcess,
}) =>
    false;

Future<void> runStartupBootstrap({
  Future<void> Function()? initializeBackgroundSync,
  Future<void> Function()? refreshBackgroundSyncSchedule,
  Future<void> Function()? initializeLocalePrefs,
  Duration taskTimeout = const Duration(seconds: 5),
}) async {
  if (initializeBackgroundSync != null) {
    await initializeBackgroundSync();
  }
  if (refreshBackgroundSyncSchedule != null) {
    await refreshBackgroundSyncSchedule();
  }
  if (initializeLocalePrefs != null) {
    await initializeLocalePrefs();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.backend,
    this.quickCaptureController,
    this.launchArgs = const DesktopLaunchArgs(),
  });

  final AppBackend? backend;
  final QuickCaptureController? quickCaptureController;
  final DesktopLaunchArgs launchArgs;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

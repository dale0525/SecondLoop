import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'core/backend/app_backend.dart';
import 'core/desktop/desktop_launch_args.dart';
import 'core/keyboard/macos_key_event_channel_normalizer.dart';
import 'core/quick_capture/quick_capture_controller.dart';
import 'core/sync/background_sync.dart';
import 'i18n/locale_prefs.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  installMacOsKeyEventChannelNormalizer();
  await BackgroundSync.init();
  await BackgroundSync.refreshSchedule();
  await AppLocaleBootstrap.ensureInitialized();

  final launchArgs = DesktopLaunchArgs.fromMainArgs(args);
  runApp(MyApp(launchArgs: launchArgs));
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
  Widget build(BuildContext context) => SecondLoopApp(
        backend: backend,
        quickCaptureController: quickCaptureController,
        launchArgs: launchArgs,
      );
}

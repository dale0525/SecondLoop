import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'core/backend/app_backend.dart';
import 'core/quick_capture/quick_capture_controller.dart';
import 'core/sync/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundSync.init();
  await BackgroundSync.refreshSchedule();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.backend, this.quickCaptureController});

  final AppBackend? backend;
  final QuickCaptureController? quickCaptureController;

  @override
  Widget build(BuildContext context) => SecondLoopApp(
      backend: backend, quickCaptureController: quickCaptureController);
}

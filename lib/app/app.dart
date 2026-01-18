import 'package:flutter/material.dart';

import '../core/app_bootstrap.dart';
import '../core/backend/app_backend.dart';
import '../core/backend/native_backend.dart';
import '../core/desktop/desktop_quick_capture_service.dart';
import '../core/quick_capture/quick_capture_controller.dart';
import '../core/quick_capture/quick_capture_scope.dart';
import 'router.dart';
import 'theme.dart';
import '../features/lock/lock_gate.dart';
import '../features/quick_capture/quick_capture_overlay.dart';
import '../core/sync/sync_engine_gate.dart';

class SecondLoopApp extends StatefulWidget {
  SecondLoopApp({
    super.key,
    AppBackend? backend,
    QuickCaptureController? quickCaptureController,
  })  : _backend = backend ?? NativeAppBackend(),
        _quickCaptureController = quickCaptureController;

  final AppBackend _backend;
  final QuickCaptureController? _quickCaptureController;

  @override
  State<SecondLoopApp> createState() => _SecondLoopAppState();
}

class _SecondLoopAppState extends State<SecondLoopApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final QuickCaptureController _quickCaptureController =
      widget._quickCaptureController ?? QuickCaptureController();

  @override
  void dispose() {
    if (widget._quickCaptureController == null) {
      _quickCaptureController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackendScope(
      backend: widget._backend,
      child: QuickCaptureScope(
        controller: _quickCaptureController,
        child: MaterialApp(
          title: 'SecondLoop',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          navigatorKey: _navigatorKey,
          home: const AppShell(),
          builder: (context, child) {
            return AppBootstrap(
              child: DesktopQuickCaptureService(
                child: LockGate(
                  child: SyncEngineGate(
                    child: QuickCaptureOverlay(
                      navigatorKey: _navigatorKey,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

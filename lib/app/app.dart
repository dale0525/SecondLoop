import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/app_bootstrap.dart';
import '../core/backend/app_backend.dart';
import '../core/backend/native_backend.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../core/cloud/cloud_auth_scope.dart';
import '../core/cloud/firebase_identity_toolkit.dart';
import '../core/subscription/cloud_subscription_controller.dart';
import '../core/subscription/subscription_scope.dart';
import '../core/desktop/desktop_quick_capture_service.dart';
import '../core/quick_capture/quick_capture_controller.dart';
import '../core/quick_capture/quick_capture_scope.dart';
import '../i18n/locale_prefs.dart';
import '../i18n/strings.g.dart';
import '../ui/sl_background.dart';
import 'router.dart';
import 'theme.dart';
import '../features/lock/lock_gate.dart';
import '../features/quick_capture/quick_capture_overlay.dart';
import '../features/share/share_ingest_gate.dart';
import '../features/share/share_intent_listener.dart';
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
  late final CloudAuthControllerImpl _cloudAuthController =
      CloudAuthControllerImpl(
    identityToolkit: FirebaseIdentityToolkitHttp(
      webApiKey: const String.fromEnvironment(
        'SECONDLOOP_FIREBASE_WEB_API_KEY',
        defaultValue: '',
      ),
    ),
  );
  late final CloudSubscriptionController _subscriptionController =
      CloudSubscriptionController(
    idTokenGetter: _cloudAuthController.getIdToken,
    cloudGatewayBaseUrl: CloudGatewayConfig.defaultConfig.baseUrl,
  );

  @override
  void initState() {
    super.initState();
    unawaited(AppLocaleBootstrap.ensureInitialized());
    _cloudAuthController.addListener(_onCloudAuthChanged);
    unawaited(_subscriptionController.refresh());
  }

  void _onCloudAuthChanged() {
    unawaited(_subscriptionController.refresh());
  }

  @override
  void dispose() {
    if (widget._quickCaptureController == null) {
      _quickCaptureController.dispose();
    }
    _cloudAuthController.removeListener(_onCloudAuthChanged);
    _cloudAuthController.dispose();
    _subscriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackendScope(
      backend: widget._backend,
      child: CloudAuthScope(
        controller: _cloudAuthController,
        child: SubscriptionScope(
          controller: _subscriptionController,
          child: QuickCaptureScope(
            controller: _quickCaptureController,
            child: TranslationProvider(
              child: Builder(
                builder: (context) {
                  final locale = TranslationProvider.of(context).flutterLocale;
                  return MaterialApp(
                    locale: TranslationProvider.of(context).flutterLocale,
                    supportedLocales: AppLocaleUtils.supportedLocales,
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    onGenerateTitle: (context) => context.t.app.title,
                    theme: AppTheme.light(locale: locale),
                    darkTheme: AppTheme.dark(locale: locale),
                    themeMode: ThemeMode.system,
                    navigatorKey: _navigatorKey,
                    home: const AppShell(),
                    builder: (context, child) {
                      return SlBackground(
                        child: AppBootstrap(
                          child: DesktopQuickCaptureService(
                            child: ShareIntentListener(
                              child: LockGate(
                                child: SyncEngineGate(
                                  child: ShareIngestGate(
                                    child: QuickCaptureOverlay(
                                      navigatorKey: _navigatorKey,
                                      child: child ?? const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

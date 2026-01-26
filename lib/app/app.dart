import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                      // NOTE: On some platforms (notably macOS), modifier keys
                      // might not be correctly reflected in `KeyEvent` state.
                      // We add a RawKeyEvent fallback to keep standard text
                      // editing shortcuts working.
                      return Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        // ignore: deprecated_member_use
                        onKey: (node, event) {
                          // ignore: deprecated_member_use
                          if (event is! RawKeyDownEvent) {
                            return KeyEventResult.ignored;
                          }
                          if (event.repeat) {
                            return KeyEventResult.ignored;
                          }

                          // ignore: deprecated_member_use
                          final metaPressed = event.isMetaPressed;
                          // ignore: deprecated_member_use
                          final controlPressed = event.isControlPressed;
                          // ignore: deprecated_member_use
                          final shiftPressed = event.isShiftPressed;
                          final hasModifier = metaPressed || controlPressed;
                          if (!hasModifier) {
                            return KeyEventResult.ignored;
                          }

                          final key = event.logicalKey;

                          Intent? intent;
                          if (key == LogicalKeyboardKey.keyA) {
                            intent = const SelectAllTextIntent(
                              SelectionChangedCause.keyboard,
                            );
                          } else if (key == LogicalKeyboardKey.keyC ||
                              key == LogicalKeyboardKey.copy) {
                            intent = CopySelectionTextIntent.copy;
                          } else if (key == LogicalKeyboardKey.keyX ||
                              key == LogicalKeyboardKey.cut) {
                            intent = const CopySelectionTextIntent.cut(
                              SelectionChangedCause.keyboard,
                            );
                          } else if (key == LogicalKeyboardKey.keyV ||
                              key == LogicalKeyboardKey.paste) {
                            intent = const PasteTextIntent(
                              SelectionChangedCause.keyboard,
                            );
                          } else if (key == LogicalKeyboardKey.keyZ &&
                              !shiftPressed) {
                            intent = const UndoTextIntent(
                              SelectionChangedCause.keyboard,
                            );
                          } else if (key == LogicalKeyboardKey.keyY ||
                              (key == LogicalKeyboardKey.keyZ &&
                                  shiftPressed)) {
                            intent = const RedoTextIntent(
                              SelectionChangedCause.keyboard,
                            );
                          }

                          if (intent == null) {
                            return KeyEventResult.ignored;
                          }

                          final focusContext =
                              FocusManager.instance.primaryFocus?.context;
                          if (focusContext == null) {
                            return KeyEventResult.ignored;
                          }

                          final action = Actions.maybeFind<Intent>(
                            focusContext,
                            intent: intent,
                          );
                          if (action == null || !action.isEnabled(intent)) {
                            return KeyEventResult.ignored;
                          }

                          Actions.invoke(focusContext, intent);
                          return KeyEventResult.handled;
                        },
                        child: Shortcuts(
                          shortcuts: const <ShortcutActivator, Intent>{
                            SingleActivator(LogicalKeyboardKey.keyC,
                                control: true): CopySelectionTextIntent.copy,
                            SingleActivator(LogicalKeyboardKey.keyC,
                                meta: true): CopySelectionTextIntent.copy,
                            SingleActivator(LogicalKeyboardKey.copy):
                                CopySelectionTextIntent.copy,
                            SingleActivator(LogicalKeyboardKey.keyV,
                                    control: true):
                                PasteTextIntent(SelectionChangedCause.keyboard),
                            SingleActivator(LogicalKeyboardKey.keyV,
                                    meta: true):
                                PasteTextIntent(SelectionChangedCause.keyboard),
                            SingleActivator(LogicalKeyboardKey.paste):
                                PasteTextIntent(SelectionChangedCause.keyboard),
                            SingleActivator(LogicalKeyboardKey.keyX,
                                control: true): CopySelectionTextIntent.cut(
                              SelectionChangedCause.keyboard,
                            ),
                            SingleActivator(LogicalKeyboardKey.keyX,
                                meta: true): CopySelectionTextIntent.cut(
                              SelectionChangedCause.keyboard,
                            ),
                            SingleActivator(LogicalKeyboardKey.cut):
                                CopySelectionTextIntent.cut(
                              SelectionChangedCause.keyboard,
                            ),
                            SingleActivator(LogicalKeyboardKey.keyA,
                                    control: true):
                                SelectAllTextIntent(
                                    SelectionChangedCause.keyboard),
                            SingleActivator(LogicalKeyboardKey.keyA,
                                    meta: true):
                                SelectAllTextIntent(
                                    SelectionChangedCause.keyboard),
                          },
                          child: SlBackground(
                            child: AppBootstrap(
                              child: DesktopQuickCaptureService(
                                child: ShareIntentListener(
                                  child: LockGate(
                                    child: SyncEngineGate(
                                      child: ShareIngestGate(
                                        child: QuickCaptureOverlay(
                                          navigatorKey: _navigatorKey,
                                          child:
                                              child ?? const SizedBox.shrink(),
                                        ),
                                      ),
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

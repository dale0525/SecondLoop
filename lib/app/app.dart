import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/app_bootstrap.dart';
import '../core/ai/embeddings_index_gate.dart';
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
import '../core/sync/cloud_sync_switch_prompt_gate.dart';
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
                          bool isTextEditingShortcutChar(String char) =>
                              char == 'a' ||
                              char == 'c' ||
                              char == 'v' ||
                              char == 'x' ||
                              char == 'z' ||
                              char == 'y';

                          String? keyChar;
                          final keyLabel = event.data.keyLabel;
                          if (keyLabel.length == 1) {
                            final lowered = keyLabel.toLowerCase();
                            if (isTextEditingShortcutChar(lowered)) {
                              keyChar = lowered;
                            }
                          }
                          if (keyChar == null) {
                            final rawChar = event.character;
                            if (rawChar != null && rawChar.length == 1) {
                              final lowered = rawChar.toLowerCase();
                              if (isTextEditingShortcutChar(lowered)) {
                                keyChar = lowered;
                              }
                            }
                          }

                          Intent? intent;
                          switch (keyChar) {
                            case 'a':
                              intent = const SelectAllTextIntent(
                                SelectionChangedCause.keyboard,
                              );
                              break;
                            case 'c':
                              intent = CopySelectionTextIntent.copy;
                              break;
                            case 'x':
                              intent = const CopySelectionTextIntent.cut(
                                SelectionChangedCause.keyboard,
                              );
                              break;
                            case 'v':
                              intent = const PasteTextIntent(
                                SelectionChangedCause.keyboard,
                              );
                              break;
                            case 'z':
                              intent = shiftPressed
                                  ? const RedoTextIntent(
                                      SelectionChangedCause.keyboard,
                                    )
                                  : const UndoTextIntent(
                                      SelectionChangedCause.keyboard,
                                    );
                              break;
                            case 'y':
                              intent = const RedoTextIntent(
                                SelectionChangedCause.keyboard,
                              );
                              break;
                          }

                          if (intent == null) {
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
                            CharacterActivator('c', control: true):
                                CopySelectionTextIntent.copy,
                            CharacterActivator('c', meta: true):
                                CopySelectionTextIntent.copy,
                            SingleActivator(LogicalKeyboardKey.keyC,
                                control: true): CopySelectionTextIntent.copy,
                            SingleActivator(LogicalKeyboardKey.keyC,
                                meta: true): CopySelectionTextIntent.copy,
                            SingleActivator(LogicalKeyboardKey.copy):
                                CopySelectionTextIntent.copy,
                            CharacterActivator('v', control: true):
                                PasteTextIntent(SelectionChangedCause.keyboard),
                            CharacterActivator('v', meta: true):
                                PasteTextIntent(SelectionChangedCause.keyboard),
                            SingleActivator(LogicalKeyboardKey.keyV,
                                    control: true):
                                PasteTextIntent(SelectionChangedCause.keyboard),
                            SingleActivator(LogicalKeyboardKey.keyV,
                                    meta: true):
                                PasteTextIntent(SelectionChangedCause.keyboard),
                            SingleActivator(LogicalKeyboardKey.paste):
                                PasteTextIntent(SelectionChangedCause.keyboard),
                            CharacterActivator('x', control: true):
                                CopySelectionTextIntent.cut(
                              SelectionChangedCause.keyboard,
                            ),
                            CharacterActivator('x', meta: true):
                                CopySelectionTextIntent.cut(
                              SelectionChangedCause.keyboard,
                            ),
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
                            CharacterActivator('a', control: true):
                                SelectAllTextIntent(
                              SelectionChangedCause.keyboard,
                            ),
                            CharacterActivator('a', meta: true):
                                SelectAllTextIntent(
                              SelectionChangedCause.keyboard,
                            ),
                          },
                          child: SlBackground(
                            child: AppBootstrap(
                              child: DesktopQuickCaptureService(
                                child: ShareIntentListener(
                                  child: LockGate(
                                    child: SyncEngineGate(
                                      child: EmbeddingsIndexGate(
                                        child: CloudSyncSwitchPromptGate(
                                          navigatorKey: _navigatorKey,
                                          child: ShareIngestGate(
                                            child: QuickCaptureOverlay(
                                              navigatorKey: _navigatorKey,
                                              child: child ??
                                                  const SizedBox.shrink(),
                                            ),
                                          ),
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

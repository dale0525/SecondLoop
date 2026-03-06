import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/app_bootstrap.dart';
import '../core/ai/embeddings_index_gate.dart';
import '../core/ai/message_embeddings_index_gate.dart';
import '../core/ai/semantic_parse_auto_actions_gate.dart';
import '../core/ai/detached_ask_recovery_gate.dart';
import '../core/backend/app_backend.dart';
import '../core/backend/native_backend.dart';
import '../core/cloud/cloud_auth_access.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../core/cloud/cloud_auth_scope.dart';
import '../core/cloud/firebase_identity_toolkit.dart';
import '../core/media_enrichment/media_enrichment_gate.dart';
import '../core/subscription/cloud_subscription_controller.dart';
import '../core/subscription/subscription_scope.dart';
import '../core/desktop/desktop_background_service.dart';
import '../core/desktop/desktop_launch_args.dart';
import '../core/desktop/desktop_quick_capture_service.dart';
import '../core/quick_capture/quick_capture_controller.dart';
import '../core/quick_capture/quick_capture_scope.dart';
import '../core/update/auto_upgrade_gate.dart';
import '../core/update/update_badge_prefs.dart';
import '../core/update/release_notes_first_launch_gate.dart';
import '../i18n/locale_prefs.dart';
import '../i18n/strings.g.dart';
import '../ui/sl_background.dart';
import 'router.dart';
import 'theme.dart';
import 'theme_palette_prefs.dart';
import 'theme_mode_prefs.dart';
import '../features/lock/lock_gate.dart';
import '../features/quick_capture/quick_capture_overlay.dart';
import '../features/share/share_ingest_gate.dart';
import '../features/settings/settings_page.dart';
import '../features/share/share_intent_listener.dart';
import '../features/welcome/first_launch_welcome_gate.dart';
import '../core/sync/cloud_sync_switch_prompt_gate.dart';
import '../core/sync/sync_engine_gate.dart';
import '../core/notifications/review_reminder_notifications_gate.dart';
import 'text_editing_shortcuts.dart';

class SecondLoopApp extends StatefulWidget {
  SecondLoopApp({
    super.key,
    AppBackend? backend,
    QuickCaptureController? quickCaptureController,
    this.launchArgs = const DesktopLaunchArgs(),
  })  : _backend = backend ?? NativeAppBackend(),
        _quickCaptureController = quickCaptureController;

  final AppBackend _backend;
  final QuickCaptureController? _quickCaptureController;
  final DesktopLaunchArgs launchArgs;

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
    idTokenGetter: () => readCloudAuthIdToken(
      _cloudAuthController,
      mode: CloudAuthAccessMode.background,
    ),
    cloudGatewayBaseUrl: CloudGatewayConfig.defaultConfig.baseUrl,
  );

  @override
  void initState() {
    super.initState();
    unawaited(AppLocaleBootstrap.ensureInitialized());
    unawaited(AppThemeModePrefs.ensureInitialized());
    unawaited(AppThemePalettePrefs.ensureInitialized());
    unawaited(UpdateBadgePrefs.ensureInitialized());
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
                  return ListenableBuilder(
                    listenable: Listenable.merge([
                      AppThemeModePrefs.value,
                      AppThemePalettePrefs.value,
                    ]),
                    builder: (context, _) {
                      final themeMode = AppThemeModePrefs.value.value;
                      final palette = AppThemePalettePrefs.value.value;
                      return MaterialApp(
                        locale: TranslationProvider.of(context).flutterLocale,
                        supportedLocales: AppLocaleUtils.supportedLocales,
                        localizationsDelegates:
                            GlobalMaterialLocalizations.delegates,
                        onGenerateTitle: (context) => context.t.app.title,
                        theme: AppTheme.light(locale: locale, palette: palette),
                        darkTheme:
                            AppTheme.dark(locale: locale, palette: palette),
                        themeMode: themeMode,
                        navigatorKey: _navigatorKey,
                        home: const AutoUpgradeGate(
                          child: ReleaseNotesFirstLaunchGate(
                            child: AppShell(),
                          ),
                        ),
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
                              final key = event.logicalKey;
                              final shortcut = resolveTextEditingShortcut(
                                key: key,
                                keyLabel: event.data.keyLabel,
                                character: event.character,
                                metaPressed: metaPressed,
                                controlPressed: controlPressed,
                                shiftPressed: shiftPressed,
                                supportedShortcuts: const <TextEditingShortcut>{
                                  TextEditingShortcut.selectAll,
                                  TextEditingShortcut.copy,
                                  TextEditingShortcut.paste,
                                  TextEditingShortcut.cut,
                                  TextEditingShortcut.undo,
                                  TextEditingShortcut.redo,
                                },
                              );
                              if (shortcut == null) {
                                return KeyEventResult.ignored;
                              }

                              Intent? intent;
                              switch (shortcut) {
                                case TextEditingShortcut.selectAll:
                                  intent = const SelectAllTextIntent(
                                    SelectionChangedCause.keyboard,
                                  );
                                  break;
                                case TextEditingShortcut.copy:
                                  intent = CopySelectionTextIntent.copy;
                                  break;
                                case TextEditingShortcut.paste:
                                  intent = const PasteTextIntent(
                                    SelectionChangedCause.keyboard,
                                  );
                                  break;
                                case TextEditingShortcut.cut:
                                  intent = const CopySelectionTextIntent.cut(
                                    SelectionChangedCause.keyboard,
                                  );
                                  break;
                                case TextEditingShortcut.undo:
                                  intent = const UndoTextIntent(
                                    SelectionChangedCause.keyboard,
                                  );
                                  break;
                                case TextEditingShortcut.redo:
                                  intent = const RedoTextIntent(
                                    SelectionChangedCause.keyboard,
                                  );
                                  break;
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
                                        control: true):
                                    CopySelectionTextIntent.copy,
                                SingleActivator(LogicalKeyboardKey.keyC,
                                    meta: true): CopySelectionTextIntent.copy,
                                SingleActivator(LogicalKeyboardKey.copy):
                                    CopySelectionTextIntent.copy,
                                CharacterActivator('v', control: true):
                                    PasteTextIntent(
                                        SelectionChangedCause.keyboard),
                                CharacterActivator('v', meta: true):
                                    PasteTextIntent(
                                        SelectionChangedCause.keyboard),
                                SingleActivator(LogicalKeyboardKey.keyV,
                                        control: true):
                                    PasteTextIntent(
                                        SelectionChangedCause.keyboard),
                                SingleActivator(LogicalKeyboardKey.keyV,
                                        meta: true):
                                    PasteTextIntent(
                                        SelectionChangedCause.keyboard),
                                SingleActivator(LogicalKeyboardKey.paste):
                                    PasteTextIntent(
                                        SelectionChangedCause.keyboard),
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
                                  child: DesktopBackgroundService(
                                    silentStartupRequested: widget
                                        .launchArgs.silentStartupRequested,
                                    onOpenSettingsRequested: () async {
                                      final navigator =
                                          _navigatorKey.currentState;
                                      if (navigator == null) return;
                                      await navigator.push(
                                        MaterialPageRoute(
                                          builder: (_) => const SettingsPage(),
                                        ),
                                      );
                                    },
                                    child: DesktopQuickCaptureService(
                                      child: ShareIntentListener(
                                        child: LockGate(
                                          child: SyncEngineGate(
                                            child: DetachedAskRecoveryGate(
                                              child:
                                                  ReviewReminderNotificationsGate(
                                                navigatorKey: _navigatorKey,
                                                child: MediaEnrichmentGate(
                                                  child:
                                                      SemanticParseAutoActionsGate(
                                                    child:
                                                        MessageEmbeddingsIndexGate(
                                                      child:
                                                          EmbeddingsIndexGate(
                                                        child:
                                                            CloudSyncSwitchPromptGate(
                                                          navigatorKey:
                                                              _navigatorKey,
                                                          child:
                                                              ShareIngestGate(
                                                            child:
                                                                QuickCaptureOverlay(
                                                              navigatorKey:
                                                                  _navigatorKey,
                                                              child:
                                                                  FirstLaunchWelcomeGate(
                                                                child: child ??
                                                                    const SizedBox
                                                                        .shrink(),
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

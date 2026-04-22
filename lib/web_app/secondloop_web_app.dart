import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme_mode_prefs.dart';
import '../app/theme_palette_prefs.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../core/cloud/firebase_identity_toolkit.dart';
import '../i18n/locale_prefs.dart';
import '../i18n/strings.g.dart';
import 'web_entry_intent.dart';
import 'web_app_gate.dart';
import 'web_app_theme.dart';
import 'web_native_runtime_support.dart';

export 'web_entry_intent.dart' show WebEntryIntent, parseWebEntryIntent;

class SecondLoopWebApp extends StatefulWidget {
  const SecondLoopWebApp({
    super.key,
    this.bootstrapLoader,
    this.configLoader,
    this.serviceFactory,
    this.authControllerFactory,
    this.entryIntent,
    this.webNativeRuntimeSupported,
  });

  final Future<WebAppBootstrapData> Function()? bootstrapLoader;
  final Future<WebAppConfig> Function()? configLoader;
  final WebAppService Function(WebAppConfig config)? serviceFactory;
  final ObservableCloudAuthController Function(WebAppConfig config)?
      authControllerFactory;
  final WebEntryIntent? entryIntent;
  final bool Function()? webNativeRuntimeSupported;

  @override
  State<SecondLoopWebApp> createState() => _SecondLoopWebAppState();
}

class _SecondLoopWebAppState extends State<SecondLoopWebApp> {
  Future<WebAppBootstrapData>? _bootstrapFuture;
  WebAppService? _bootstrappedService;
  ObservableCloudAuthController? _bootstrappedAuthController;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeUiPrefs());
    _bootstrapFuture = (widget.bootstrapLoader ?? _bootstrap)();
  }

  Future<void> _initializeUiPrefs() async {
    if (LocaleSettings.currentLocale == AppLocale.en) {
      await AppLocaleBootstrap.ensureInitialized();
    }
    await AppThemeModePrefs.ensureInitialized();
    await AppThemePalettePrefs.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(AppThemeModePrefs.prefsKey)) {
      AppThemeModePrefs.value.value = ThemeMode.light;
    }
    if (!prefs.containsKey(AppThemePalettePrefs.prefsKey)) {
      AppThemePalettePrefs.value.value = AppThemePalette.monochrome;
    }
  }

  Future<WebAppBootstrapData> _bootstrap() async {
    final config =
        await (widget.configLoader ?? WebAppServiceHttp.loadConfig)();
    final service = (widget.serviceFactory ??
        (config) => WebAppServiceHttp(
              managedVaultConfigured: config.hasManagedVaultBaseUrl,
            ))(config);
    final authController = (widget.authControllerFactory ??
        (config) => CloudAuthControllerImpl(
              identityToolkit: FirebaseIdentityToolkitHttp(
                webApiKey: config.firebaseWebApiKey,
              ),
            ))(config);
    try {
      await authController.refreshUserInfo();
    } catch (_) {
      // Allow the app to continue booting so the gate can render sign-in and
      // retry paths even if the initial profile refresh fails.
    }
    final supportsNativeRuntime =
        (widget.webNativeRuntimeSupported ?? browserSupportsWebNativeRuntime)();
    if (!supportsNativeRuntime) {
      service.close();
      _disposeAuthController(authController);
      throw UnsupportedError(
        'web native runtime is required for /app and needs '
        'SharedArrayBuffer with cross-origin isolation support',
      );
    }
    if (!mounted) {
      service.close();
      _disposeAuthController(authController);
    } else {
      _bootstrappedService = service;
      _bootstrappedAuthController = authController;
    }
    return WebAppBootstrapData(
      authController: authController,
      service: service,
      managedVaultBaseUrl: config.managedVaultBaseUrl,
    );
  }

  @override
  void dispose() {
    _bootstrappedService?.close();
    _bootstrappedService = null;
    _disposeAuthController(_bootstrappedAuthController);
    _bootstrappedAuthController = null;
    super.dispose();
  }

  void _disposeAuthController(ObservableCloudAuthController? controller) {
    if (controller is ChangeNotifier) {
      (controller as ChangeNotifier).dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entryIntent = widget.entryIntent ?? parseWebEntryIntent(Uri.base);

    return TranslationProvider(
      child: Builder(
        builder: (context) {
          final locale = TranslationProvider.of(context).flutterLocale;
          return MaterialApp(
            locale: locale,
            supportedLocales: AppLocaleUtils.supportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            title: context.t.app.web.title,
            theme: buildSecondLoopWebTheme(locale: locale),
            themeMode: ThemeMode.light,
            builder: (context, child) {
              return SecondLoopWebAppFrame(
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: FutureBuilder<WebAppBootstrapData>(
              future: _bootstrapFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Scaffold(
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(context.t.app.web
                            .bootstrapFailed(error: '${snapshot.error}')),
                      ),
                    ),
                  );
                }

                return WebAppGate(
                  authController: snapshot.data!.authController,
                  service: snapshot.data!.service,
                  entryIntent: entryIntent,
                  managedVaultBaseUrl: snapshot.data!.managedVaultBaseUrl,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class WebAppBootstrapData {
  const WebAppBootstrapData({
    required this.authController,
    required this.service,
    required this.managedVaultBaseUrl,
  });

  final ObservableCloudAuthController authController;
  final WebAppService service;
  final String managedVaultBaseUrl;
}

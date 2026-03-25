import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/backend/cloud_web_backend.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../core/cloud/firebase_identity_toolkit.dart';
import '../i18n/strings.g.dart';
import 'web_app_gate.dart';

class SecondLoopWebApp extends StatefulWidget {
  const SecondLoopWebApp({
    super.key,
    this.bootstrapLoader,
    this.configLoader,
    this.serviceFactory,
    this.authControllerFactory,
  });

  final Future<WebAppBootstrapData> Function()? bootstrapLoader;
  final Future<WebAppConfig> Function()? configLoader;
  final WebAppService Function()? serviceFactory;
  final ObservableCloudAuthController Function(WebAppConfig config)?
      authControllerFactory;

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
    _bootstrapFuture = (widget.bootstrapLoader ?? _bootstrap)();
  }

  Future<WebAppBootstrapData> _bootstrap() async {
    final config =
        await (widget.configLoader ?? WebAppServiceHttp.loadConfig)();
    final service = (widget.serviceFactory ?? () => WebAppServiceHttp())();
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
      chatBackend: CloudWebBackend(
        chatClient: _WebAppCloudWebChatClient(service: service),
        fetchTaskPriorityAssessments: ({
          required idToken,
          required cacheScopeKey,
        }) =>
            service.fetchTaskPriorityAssessments(
          idToken: idToken,
          scope: cacheScopeKey,
        ),
        upsertTaskPriorityAssessments: ({
          required idToken,
          required payload,
        }) =>
            service.upsertTaskPriorityAssessments(
          idToken: idToken,
          payload: payload,
        ),
      ),
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
    return TranslationProvider(
      child: Builder(
        builder: (context) {
          return MaterialApp(
            locale: TranslationProvider.of(context).flutterLocale,
            supportedLocales: AppLocaleUtils.supportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            title: context.t.app.web.title,
            theme: ThemeData(
              colorScheme:
                  ColorScheme.fromSeed(seedColor: const Color(0xFF5B6CFF)),
              useMaterial3: true,
            ),
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
                  chatBackend: snapshot.data!.chatBackend,
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
    required this.chatBackend,
  });

  final ObservableCloudAuthController authController;
  final WebAppService service;
  final CloudWebBackend chatBackend;
}

final class _WebAppCloudWebChatClient implements CloudWebChatClient {
  const _WebAppCloudWebChatClient({required this.service});

  final WebAppService service;

  @override
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  }) {
    // Web does not honor client-side model overrides.
    // The site backend chooses the server-owned model for Pro users.
    return service.sendChat(
      idToken: idToken,
      messages: messages,
    );
  }
}

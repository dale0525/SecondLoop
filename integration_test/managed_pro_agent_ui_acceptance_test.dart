import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/router.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_auth_store.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/cloud_subscription_controller.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/update/update_badge_prefs.dart';
import 'package:secondloop/features/agent_ui/agent_ui_acceptance_driver.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/ui/sl_background.dart';

import '../test/test_backend.dart';
import '../test/test_i18n.dart';

const _redactedManagedProAccountLabel = 'managed-pro-account';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
  });

  testWidgets('managed pro agent UI acceptance screenshots', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final credentials = _managedProCredentials();
    final screenshotKey = GlobalKey(debugLabel: 'managed_pro_acceptance_root');
    final agentUiAcceptanceController = AgentUiAcceptanceController(
      redactedCloudAccountEmail: _redactedManagedProAccountLabel,
    );
    final cloudAuthController = CloudAuthControllerImpl(
      identityToolkit: FirebaseIdentityToolkitHttp(
        webApiKey: const String.fromEnvironment(
          'SECONDLOOP_FIREBASE_WEB_API_KEY',
          defaultValue: '',
        ),
      ),
      store: _InMemoryCloudAuthStore(),
    );
    final subscriptionController = CloudSubscriptionController(
      idTokenGetter: cloudAuthController.getIdToken,
      cloudGatewayBaseUrl: CloudGatewayConfig.defaultConfig.baseUrl,
    );
    addTearDown(() async {
      agentUiAcceptanceController.dispose();
      await cloudAuthController.signOut();
      subscriptionController.dispose();
      cloudAuthController.dispose();
    });

    await tester.pumpWidget(
      _ManagedProAcceptanceApp(
        screenshotKey: screenshotKey,
        cloudAuthController: cloudAuthController,
        subscriptionController: subscriptionController,
        agentUiAcceptanceController: agentUiAcceptanceController,
      ),
    );
    await tester.pumpAndSettle();
    agentUiAcceptanceController.simulateManagedProConversationWorkspace();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agent_conversation_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat_input')), findsOneWidget);

    final outputDir = _acceptanceOutputDirectory();
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '01-conversation-home',
    );

    await tester.ensureVisible(find.text('Fields'));
    await tester.tap(find.text('Fields'));
    await tester.pumpAndSettle();
    expect(find.text('Extracted fields'), findsOneWidget);
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '02-conversation-media-fields',
    );

    await tester.tap(find.text('Review').first);
    await tester.pumpAndSettle();
    expect(find.text('Needs your OK queue'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Move passport renewal'), findsNothing);
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '03-review-approve-flow',
    );

    await tester.tap(find.text('Memory').first);
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '04-memory-preferences',
    );

    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    await _writeScreenshot(
      rootKey: screenshotKey,
      outputDir: outputDir,
      name: '05-settings-account',
    );

    await _signInManagedProAccount(
      tester: tester,
      rootKey: screenshotKey,
      outputDir: outputDir,
      credentials: credentials,
      cloudAuthController: cloudAuthController,
      subscriptionController: subscriptionController,
    );

    await _writeReport(
      outputDir,
      cloudAuthController: cloudAuthController,
      subscriptionController: subscriptionController,
    );
  });
}

_ManagedProCredentials _managedProCredentials() {
  final email =
      (Platform.environment['SECONDLOOP_MANAGED_PRO_EMAIL'] ?? '').trim();
  final password =
      Platform.environment['SECONDLOOP_MANAGED_PRO_PASSWORD'] ?? '';
  expect(
    email,
    isNotEmpty,
    reason: 'missing required SECONDLOOP_MANAGED_PRO_EMAIL',
  );
  expect(
    password,
    isNotEmpty,
    reason: 'missing required SECONDLOOP_MANAGED_PRO_PASSWORD',
  );
  return _ManagedProCredentials(email: email, password: password);
}

Future<void> _signInManagedProAccount({
  required WidgetTester tester,
  required GlobalKey rootKey,
  required Directory outputDir,
  required _ManagedProCredentials credentials,
  required CloudAuthControllerImpl cloudAuthController,
  required CloudSubscriptionController subscriptionController,
}) async {
  final cloudAccountLink = find.text('Open Cloud account').first;
  await tester.ensureVisible(cloudAccountLink);
  await tester.tap(cloudAccountLink);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('cloud_sign_in')), findsOneWidget);
  await _writeScreenshot(
    rootKey: rootKey,
    outputDir: outputDir,
    name: '06-managed-pro-cloud-account-form',
  );

  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), credentials.email);
  await tester.enterText(fields.at(1), credentials.password);
  await tester.tap(find.byKey(const ValueKey('cloud_sign_in')));
  await _pumpUntil(
    tester,
    () => cloudAuthController.uid != null,
    timeout: const Duration(seconds: 30),
    reason: 'managed pro sign-in did not produce a Firebase uid',
  );
  await _pumpUntil(
    tester,
    () => cloudAuthController.email == credentials.email,
    timeout: const Duration(seconds: 30),
    reason: 'managed pro signed-in account info was not refreshed',
  );
  expect(find.textContaining(credentials.email), findsNothing);
  expect(find.textContaining(_redactedManagedProAccountLabel), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('cloud_subscription_refresh')));
  await _pumpUntil(
    tester,
    () => subscriptionController.status == SubscriptionStatus.entitled,
    timeout: const Duration(seconds: 30),
    reason: 'managed pro subscription did not become entitled',
  );
  await _writeScreenshot(
    rootKey: rootKey,
    outputDir: outputDir,
    name: '07-managed-pro-cloud-account-signed-in',
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(condition(), isTrue, reason: reason);
}

Directory _acceptanceOutputDirectory() {
  final raw =
      Platform.environment['SECONDLOOP_MANAGED_PRO_ACCEPTANCE_OUTPUT_DIR'];
  final path = raw == null || raw.trim().isEmpty
      ? 'build/managed_pro_acceptance/local_${DateTime.now().millisecondsSinceEpoch}'
      : raw.trim();
  return Directory(path)..createSync(recursive: true);
}

Future<void> _writeScreenshot({
  required GlobalKey rootKey,
  required Directory outputDir,
  required String name,
}) async {
  final bytes = await _captureRepaintBoundaryPng(rootKey);
  expect(bytes.length, greaterThan(1000));
  await File('${outputDir.path}/$name.png').writeAsBytes(bytes);
}

Future<Uint8List> _captureRepaintBoundaryPng(GlobalKey rootKey) async {
  final renderObject = rootKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    throw StateError('Acceptance screenshot root is not ready');
  }

  final image = await renderObject.toImage();
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Could not encode acceptance screenshot');
    }
    return byteData.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<void> _writeReport(
  Directory outputDir, {
  required CloudAuthControllerImpl cloudAuthController,
  required CloudSubscriptionController subscriptionController,
}) async {
  final report = <String, Object?>{
    'schema': 'managed_pro_agent_ui_acceptance_v1',
    'appId': Platform.environment['SECONDLOOP_APP_ID'],
    'appName': Platform.environment['SECONDLOOP_APP_NAME'],
    'managedProEmailSet':
        (Platform.environment['SECONDLOOP_MANAGED_PRO_EMAIL'] ?? '').isNotEmpty,
    'conversationPath': {
      'usesDefaultAppShell': true,
      'usesAgentConversationPage': true,
      'appExposedInterface':
          'AgentUiAcceptanceController.simulateManagedProConversationWorkspace',
    },
    'screenshotRedaction': {
      'cloudAccountEmail': 'redacted',
    },
    'managedProSignIn': {
      'uidPresent': cloudAuthController.uid != null,
      'emailVerified': cloudAuthController.emailVerified,
      'subscriptionStatus': subscriptionController.status.name,
      'gatewayBaseUrlSet': CloudGatewayConfig.defaultConfig.baseUrl.isNotEmpty,
    },
    'screenshots': [
      '01-conversation-home.png',
      '02-conversation-media-fields.png',
      '03-review-approve-flow.png',
      '04-memory-preferences.png',
      '05-settings-account.png',
      '06-managed-pro-cloud-account-form.png',
      '07-managed-pro-cloud-account-signed-in.png',
    ],
  };
  const encoder = JsonEncoder.withIndent('  ');
  await File('${outputDir.path}/managed_pro_agent_ui_acceptance_report.json')
      .writeAsString('${encoder.convert(report)}\n');
}

final class _ManagedProAcceptanceApp extends StatelessWidget {
  const _ManagedProAcceptanceApp({
    required this.screenshotKey,
    required this.cloudAuthController,
    required this.subscriptionController,
    required this.agentUiAcceptanceController,
  });

  final GlobalKey screenshotKey;
  final CloudAuthControllerImpl cloudAuthController;
  final CloudSubscriptionController subscriptionController;
  final AgentUiAcceptanceController agentUiAcceptanceController;

  @override
  Widget build(BuildContext context) {
    return CloudAuthScope(
      controller: cloudAuthController,
      child: SubscriptionScope(
        controller: subscriptionController,
        child: RepaintBoundary(
          key: screenshotKey,
          child: wrapWithI18n(
            AgentUiAcceptanceScope(
              controller: agentUiAcceptanceController,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light(
                  locale: LocaleSettings.currentLocale.flutterLocale,
                ),
                home: SlBackground(
                  child: AppPlatformCapabilityScope(
                    capabilities: const AppPlatformCapabilities(
                      supportsDesktopHotkey: true,
                      supportsBiometricUnlock: false,
                      supportsAudioRecording: false,
                      supportsDesktopDrop: true,
                      supportsDesktopBootSettings: true,
                      supportsCameraCapture: false,
                      usesCloudSessionModel: false,
                    ),
                    child: AppBackendScope(
                      backend: TestAppBackend(),
                      child: SessionScope(
                        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                        lock: () {},
                        child: const AppShell(),
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
  }
}

final class _ManagedProCredentials {
  const _ManagedProCredentials({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}

final class _InMemoryCloudAuthStore implements CloudAuthStore {
  CloudAuthStoredSession? _session;

  @override
  Future<void> clear() async {
    _session = null;
  }

  @override
  Future<CloudAuthStoredSession?> load() async {
    return _session;
  }

  @override
  Future<void> save(CloudAuthStoredSession session) async {
    _session = session;
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/cloud_runtime_mode_page.dart';
import 'package:secondloop/features/welcome/welcome_page.dart';
import 'package:secondloop/features/welcome/welcome_status.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  Future<void> bringIntoView(WidgetTester tester, Finder target) async {
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isEmpty) return;
    await tester.dragUntilVisible(
      target,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpWelcomePage(
    WidgetTester tester, {
    AppBackend? backend,
    Uint8List? sessionKey,
    required VoidCallback onSkip,
    required VoidCallback onFinish,
    WelcomeGuideStatusLoader? statusLoader,
    WelcomeGuideUriLauncher? uriLauncher,
    CloudAuthController? cloudAuthController,
    CloudGatewayConfig cloudGatewayConfig = CloudGatewayConfig.defaultConfig,
    SubscriptionStatusController? subscriptionController,
  }) async {
    Widget app = wrapWithI18n(
      MaterialApp(
        home: WelcomePage(
          onSkipForNow: onSkip,
          onFinishSetup: onFinish,
          statusLoader: statusLoader ?? loadWelcomeGuideStatus,
          uriLauncher: uriLauncher,
        ),
      ),
    );

    if (backend != null) {
      app = AppBackendScope(
        backend: backend,
        child: app,
      );
    }

    if (cloudAuthController != null) {
      app = CloudAuthScope(
        controller: cloudAuthController,
        gatewayConfig: cloudGatewayConfig,
        child: app,
      );
    }

    if (subscriptionController != null) {
      app = SubscriptionScope(
        controller: subscriptionController,
        child: app,
      );
    }

    if (sessionKey != null) {
      app = SessionScope(
        sessionKey: sessionKey,
        lock: () {},
        child: app,
      );
    }

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('renders three setup cards and footer actions', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
    );

    expect(find.byKey(const ValueKey('welcome_guide_header_title')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_header_subtitle')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_ai')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('welcome_guide_card_sync')), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_permissions')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_skip')), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_finish')), findsOneWidget);
  });

  testWidgets('fires callbacks when tapping skip and finish', (tester) async {
    SharedPreferences.setMockInitialValues({});

    var skipTapped = false;
    var finishTapped = false;

    await pumpWelcomePage(
      tester,
      onSkip: () => skipTapped = true,
      onFinish: () => finishTapped = true,
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('welcome_guide_skip')));
    await tester.pump();

    expect(skipTapped, isTrue);

    await tester.tap(find.byKey(const ValueKey('welcome_guide_finish')));
    await tester.pump();

    expect(finishTapped, isTrue);
  });

  testWidgets('AI status shows ready when at least one route is available',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      backend: TestAppBackend(),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
      cloudAuthController: _FakeCloudAuthController(),
      cloudGatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://gateway.example.test',
        modelName: 'cloud',
      ),
      subscriptionController: _FakeSubscriptionController(),
      onSkip: () {},
      onFinish: () {},
    );

    expect(find.byKey(const ValueKey('welcome_guide_ai_status_ready')),
        findsOneWidget);
  });

  testWidgets('sync status shows ready when configured sync exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeWebdavBaseUrl('https://example.com/webdav');
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 9)));

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
    );

    expect(find.byKey(const ValueKey('welcome_guide_sync_status_ready')),
        findsOneWidget);
  });

  testWidgets('opens AI settings from AI card', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      backend: TestAppBackend(),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('welcome_guide_card_ai_open')));
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
  });

  testWidgets('opens runtime mode from sync card', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      backend: TestAppBackend(),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('welcome_guide_card_runtime_open')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CloudRuntimeModePage), findsOneWidget);
  });

  testWidgets('permissions section renders entries and taps launcher',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final launched = <Uri>[];

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
      uriLauncher: (uri) async {
        launched.add(uri);
        return true;
      },
    );

    expect(find.byKey(const ValueKey('welcome_guide_permission_microphone')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_notifications')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_exact_alarm')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_location')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_auto_start')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_battery')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('welcome_guide_permission_speech')),
      findsNothing,
    );

    await bringIntoView(
      tester,
      find.byKey(const ValueKey('welcome_guide_permission_microphone')),
    );
    await tester
        .tap(find.byKey(const ValueKey('welcome_guide_permission_microphone')));
    await tester.pumpAndSettle();

    expect(launched, isNotEmpty);
  });

  testWidgets('hides unsupported permission entries on Windows',
      (tester) async {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});

    try {
      await pumpWelcomePage(
        tester,
        onSkip: () {},
        onFinish: () {},
        statusLoader: (_) async => const WelcomeGuideStatus(
          aiReady: false,
          syncReady: false,
        ),
        uriLauncher: (_) async => true,
      );

      expect(
        find.byKey(const ValueKey('welcome_guide_permission_microphone')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_notifications')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_auto_start')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_exact_alarm')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_location')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_battery')),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets('shows snackbar when permission settings launch fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
      uriLauncher: (_) async => false,
    );

    await bringIntoView(
      tester,
      find.byKey(const ValueKey('welcome_guide_permission_exact_alarm')),
    );
    await tester.tap(
        find.byKey(const ValueKey('welcome_guide_permission_exact_alarm')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('welcome_guide_permission_launch_failed')),
      findsOneWidget,
    );
  });

  testWidgets('permissions section auto-detects permission status',
      (tester) async {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    const permissionChannel = MethodChannel('secondloop/permissions');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    try {
      messenger.setMockMethodCallHandler(permissionChannel, (call) async {
        if (call.method != 'queryPermissionStatus') return null;
        final args = call.arguments as Map<Object?, Object?>?;
        final item = (args?['item'] as String?) ?? '';
        return switch (item) {
          'microphone' => 'enabled',
          'notifications' => 'disabled',
          _ => 'unknown',
        };
      });

      await pumpWelcomePage(
        tester,
        onSkip: () {},
        onFinish: () {},
        statusLoader: (_) async => const WelcomeGuideStatus(
          aiReady: false,
          syncReady: false,
        ),
        uriLauncher: (_) async => true,
      );

      expect(
        find.byKey(
          const ValueKey('welcome_guide_permission_status_microphone_enabled'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
              'welcome_guide_permission_status_notifications_disabled'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('welcome_guide_permission_status_auto_start_unknown'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
            const ValueKey('welcome_guide_permissions_status_needs_review')),
        findsOneWidget,
      );
    } finally {
      messenger.setMockMethodCallHandler(permissionChannel, null);
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => 'qa@example.test';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'id-token';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  @override
  SubscriptionStatus get status => SubscriptionStatus.entitled;
}

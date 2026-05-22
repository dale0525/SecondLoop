import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/app_shell_style.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/features/settings/self_managed_setup_page.dart';
import 'package:secondloop/features/welcome/welcome_page.dart';
import 'package:secondloop/features/welcome/welcome_status.dart';
import 'package:secondloop/ui/sl_surface.dart';
import 'package:secondloop/ui/sl_tokens.dart';

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
    required VoidCallback onSkip,
    required VoidCallback onFinish,
    WelcomeGuideStatusLoader? statusLoader,
    WelcomeGuideUriLauncher? uriLauncher,
    CloudAuthController? cloudAuthController,
    CloudGatewayConfig cloudGatewayConfig = CloudGatewayConfig.defaultConfig,
    SubscriptionStatusController? subscriptionController,
    ThemeData? theme,
  }) async {
    Widget app = wrapWithI18n(
      MaterialApp(
        theme: theme,
        home: WelcomePage(
          onSkipForNow: onSkip,
          onFinishSetup: onFinish,
          statusLoader: statusLoader ?? loadWelcomeGuideStatus,
          uriLauncher: uriLauncher,
        ),
      ),
    );

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

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('renders runtime mode choices before permissions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
      ),
    );

    expect(find.byKey(const ValueKey('welcome_guide_header_title')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('welcome_guide_workspace')), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_header_subtitle')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_managed_pro')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_self_managed')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('welcome_guide_shell_rail')), findsNothing);
    expect(find.text('No Cloudflare account'), findsOneWidget);
    expect(
        find.text('No Workers Paid plan or Containers setup'), findsOneWidget);
    expect(find.textContaining('Cloudflare Workers Paid plan for Containers'),
        findsOneWidget);
    expect(find.textContaining(r'$5/month'), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_ai')), findsNothing);
    expect(find.byKey(const ValueKey('welcome_guide_card_sync')), findsNothing);
    expect(find.byKey(const ValueKey('welcome_guide_card_permissions')),
        findsNothing);
    expect(find.byKey(const ValueKey('welcome_guide_skip')), findsNothing);
    expect(find.byKey(const ValueKey('welcome_guide_finish')), findsNothing);
  });

  testWidgets('starts at permissions once runtime is ready', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        runtimeMode: WelcomeGuideRuntimeMode.managedPro,
      ),
    );

    expect(find.byKey(const ValueKey('welcome_guide_card_managed_pro')),
        findsNothing);
    expect(find.byKey(const ValueKey('welcome_guide_card_self_managed')),
        findsNothing);
    expect(find.byKey(const ValueKey('welcome_guide_card_permissions')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_skip')), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_finish')), findsOneWidget);
  });

  testWidgets('reuses the app shell workspace style', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
      ),
    );

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('welcome_guide_page')),
    );
    final workspace = tester.widget<SlSurface>(
      find.byKey(const ValueKey('welcome_guide_workspace')),
    );

    expect(scaffold.backgroundColor, AppShellPalette.soft);
    expect(workspace.color, AppShellPalette.panel);
    expect(workspace.borderColor, AppShellPalette.line);
    expect(
      workspace.borderRadius,
      BorderRadius.circular(AppShellStyle.desktopShellRadius),
    );
  });

  testWidgets('uses the light onboarding theme even inside a dark app theme',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      theme: AppTheme.dark(),
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
      ),
    );

    final shellContext =
        tester.element(find.byKey(const ValueKey('welcome_guide_workspace')));
    final expectedLightTokens = AppTheme.light().extension<SlTokens>()!;

    expect(Theme.of(shellContext).brightness, Brightness.light);
    expect(
        SlTokens.of(shellContext).background, expectedLightTokens.background);
    expect(SlTokens.of(shellContext).surface, expectedLightTokens.surface);
  });

  testWidgets('fires callbacks from the permissions step', (tester) async {
    SharedPreferences.setMockInitialValues({});

    var skipTapped = false;
    var finishTapped = false;

    await pumpWelcomePage(
      tester,
      onSkip: () => skipTapped = true,
      onFinish: () => finishTapped = true,
      statusLoader: (_) async => const WelcomeGuideStatus(
        runtimeMode: WelcomeGuideRuntimeMode.managedPro,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('welcome_guide_skip')));
    await tester.pump();

    expect(skipTapped, isTrue);

    await tester.tap(find.byKey(const ValueKey('welcome_guide_finish')));
    await tester.pump();

    expect(finishTapped, isTrue);
  });

  testWidgets('managed pro account needs active subscription to be ready',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      cloudAuthController: _FakeCloudAuthController(),
      cloudGatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://gateway.example.test',
        modelName: 'cloud',
      ),
      onSkip: () {},
      onFinish: () {},
    );

    expect(find.byKey(const ValueKey('welcome_guide_card_managed_pro')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_permissions')),
        findsNothing);
  });

  testWidgets('managed pro account opens permissions after subscription active',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      cloudAuthController: _FakeCloudAuthController(),
      cloudGatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://gateway.example.test',
        modelName: 'cloud',
      ),
      subscriptionController: _FakeSubscriptionController(
        SubscriptionStatus.entitled,
      ),
      onSkip: () {},
      onFinish: () {},
    );

    expect(find.byKey(const ValueKey('welcome_guide_card_permissions')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_managed_pro')),
        findsNothing);
  });

  testWidgets('self-managed runtime opens permissions once configured',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RuntimeConnectionStore();
    await store.saveConnection(
      const CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: 'https://runtime.example.test',
          authMode: CloudRuntimeAuthMode.runtimeToken,
          authToken: 'runtime-token',
          capabilityManifestId: 'self-managed-runtime',
          manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: 'https://runtime.example.test',
          authMode: CloudRuntimeAuthMode.runtimeToken,
          capabilities: [CloudRuntimeCapability('chat')],
        ),
      ),
    );

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
    );

    expect(find.byKey(const ValueKey('welcome_guide_card_permissions')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_self_managed')),
        findsNothing);
  });

  testWidgets('returns from self-managed setup to permissions after success',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var loadCount = 0;

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async {
        loadCount += 1;
        return WelcomeGuideStatus(
          runtimeMode: loadCount == 1
              ? WelcomeGuideRuntimeMode.notConfigured
              : WelcomeGuideRuntimeMode.selfManaged,
        );
      },
    );

    final selfManagedButton =
        find.byKey(const ValueKey('welcome_guide_card_self_managed_open'));
    await bringIntoView(
      tester,
      selfManagedButton,
    );
    await tester.tap(selfManagedButton);
    await tester.pumpAndSettle();
    expect(find.byType(SelfManagedSetupPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('welcome_guide_card_permissions')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_self_managed')),
        findsNothing);
  });

  testWidgets('opens managed pro account from managed pro card',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('welcome_guide_card_managed_pro_open')));
    await tester.pumpAndSettle();

    expect(find.byType(CloudAccountPage), findsOneWidget);
  });

  testWidgets('entitled managed pro account completes onboarding from login',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var finished = false;

    await pumpWelcomePage(
      tester,
      cloudAuthController: _FakeCloudAuthController(),
      cloudGatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://gateway.example.test',
        modelName: 'cloud',
      ),
      subscriptionController: _FakeSubscriptionController(
        SubscriptionStatus.entitled,
      ),
      onSkip: () {},
      onFinish: () => finished = true,
      statusLoader: (_) async => const WelcomeGuideStatus(
        runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('welcome_guide_card_managed_pro_open')));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
  });

  testWidgets('opens self-managed setup from self-managed card',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
      ),
    );

    final selfManagedButton =
        find.byKey(const ValueKey('welcome_guide_card_self_managed_open'));
    await bringIntoView(
      tester,
      selfManagedButton,
    );
    await tester.tap(selfManagedButton);
    await tester.pumpAndSettle();

    expect(find.byType(SelfManagedSetupPage), findsOneWidget);
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
        runtimeMode: WelcomeGuideRuntimeMode.managedPro,
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
          runtimeMode: WelcomeGuideRuntimeMode.managedPro,
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
        runtimeMode: WelcomeGuideRuntimeMode.managedPro,
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
          runtimeMode: WelcomeGuideRuntimeMode.managedPro,
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
  _FakeSubscriptionController(this.status);

  @override
  final SubscriptionStatus status;
}

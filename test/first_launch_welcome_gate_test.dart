import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/features/settings/self_managed_setup_page.dart';
import 'package:secondloop/features/welcome/first_launch_welcome_gate.dart';
import 'package:secondloop/features/welcome/welcome_page.dart';

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

  Future<void> configureSelfManagedRuntime() async {
    await RuntimeConnectionStore().saveConnection(
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
  }

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: FirstLaunchWelcomeGate(
            child: Scaffold(
              body: Center(child: Text('app shell child')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows welcome when first launch flag is missing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.text('app shell child'), findsNothing);
  });

  testWidgets('shows child when first launch flag is already seen',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      FirstLaunchWelcomeGate.seenPrefsKey: true,
    });

    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(find.byType(WelcomePage), findsNothing);
    expect(find.text('app shell child'), findsOneWidget);
  });

  testWidgets('first runtime step cannot be skipped', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('welcome_guide_skip')), findsNothing);
    expect(find.byKey(const ValueKey('welcome_guide_finish')), findsNothing);
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.text('app shell child'), findsNothing);
  });

  testWidgets('skip writes seen flag from permissions step and exits welcome',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await configureSelfManagedRuntime();

    await pumpGate(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('welcome_guide_skip')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FirstLaunchWelcomeGate.seenPrefsKey), isTrue);
    expect(find.byType(WelcomePage), findsNothing);
    expect(find.text('app shell child'), findsOneWidget);
  });

  testWidgets('finish writes seen flag from permissions step and exits welcome',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await configureSelfManagedRuntime();

    await pumpGate(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('welcome_guide_finish')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FirstLaunchWelcomeGate.seenPrefsKey), isTrue);
    expect(find.byType(WelcomePage), findsNothing);
    expect(find.text('app shell child'), findsOneWidget);
  });

  testWidgets('welcome in app builder can open managed and self-managed setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: const Scaffold(
            body: Center(child: Text('app shell child')),
          ),
          builder: (context, child) {
            return FirstLaunchWelcomeGate(
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('welcome_guide_card_managed_pro_open')));
    await tester.pumpAndSettle();
    expect(find.byType(CloudAccountPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
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
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/app/app_shell_style.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/agent_ui/agent_ui_acceptance_driver.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/ui/sl_tokens.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Cloud account page shows cloud benefits before sign-in',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(home: CloudAccountPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud_account_value_props')),
        findsOneWidget);
  });

  testWidgets('Cloud account page shows subscription benefits before purchase',
      (tester) async {
    final auth = _FakeCloudAuthController();
    final subscriptions =
        _FakeSubscriptionStatusController(SubscriptionStatus.notEntitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: SubscriptionScope(
            controller: subscriptions,
            child: CloudAuthScope(
              controller: auth,
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.test',
                modelName: 'cloud',
              ),
              child: const CloudAccountPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud_subscription_value_props')),
        findsOneWidget);
  });

  testWidgets('Onboarding cloud account page keeps sign-in simple',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: CloudAccountPage(entryMode: CloudAccountEntryMode.onboarding),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('cloud_account_value_props')), findsNothing);
    expect(find.byKey(const ValueKey('cloud_subscription_value_props')),
        findsNothing);
    expect(find.byKey(const ValueKey('cloud_sign_in')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_sign_up')), findsOneWidget);
  });

  testWidgets('Onboarding auth controls use the app shell palette',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: AppTheme.light(),
          home: const CloudAccountPage(
            entryMode: CloudAccountEntryMode.onboarding,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageContext =
        tester.element(find.byKey(const ValueKey('cloud_account_page_root')));
    final fieldContext =
        tester.element(find.byKey(const ValueKey('cloud_email_field')));
    final signInContext =
        tester.element(find.byKey(const ValueKey('cloud_sign_in')));

    expect(Theme.of(pageContext).colorScheme.primary, AppShellPalette.blue);
    expect(SlTokens.of(pageContext).background, AppShellPalette.soft);
    expect(
      Theme.of(fieldContext).colorScheme.primary,
      AppShellPalette.blue,
    );
    expect(
      Theme.of(fieldContext).colorScheme.onSurfaceVariant,
      AppShellPalette.muted,
    );
    expect(SlTokens.of(fieldContext).surface2, AppShellPalette.soft);
    expect(SlTokens.of(fieldContext).borderSubtle, AppShellPalette.line);
    expect(
      Theme.of(signInContext).colorScheme.primary,
      AppShellPalette.ink,
    );
  });

  testWidgets('Onboarding auth controls adapt to the dark shell palette',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: const CloudAccountPage(
            entryMode: CloudAccountEntryMode.onboarding,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageContext =
        tester.element(find.byKey(const ValueKey('cloud_account_page_root')));
    final fieldContext =
        tester.element(find.byKey(const ValueKey('cloud_email_field')));
    final signInContext =
        tester.element(find.byKey(const ValueKey('cloud_sign_in')));

    expect(Theme.of(pageContext).colorScheme.primary, AppShellPalette.darkBlue);
    expect(SlTokens.of(pageContext).background, AppShellPalette.darkSoft);
    expect(
      Theme.of(fieldContext).colorScheme.onSurfaceVariant,
      AppShellPalette.darkMuted,
    );
    expect(SlTokens.of(fieldContext).surface2, AppShellPalette.darkSurface);
    expect(
      Theme.of(signInContext).colorScheme.primary,
      AppShellPalette.darkInk,
    );
  });

  testWidgets('Onboarding cloud account page fits narrow screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: CloudAccountPage(entryMode: CloudAccountEntryMode.onboarding),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('cloud_sign_in')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_sign_up')), findsOneWidget);
  });

  testWidgets('Onboarding not-entitled account shows subscription decision',
      (tester) async {
    final auth = _FakeCloudAuthController();
    final subscriptions =
        _FakeSubscriptionStatusController(SubscriptionStatus.notEntitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: SubscriptionScope(
            controller: subscriptions,
            child: CloudAuthScope(
              controller: auth,
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.test',
                modelName: 'cloud',
              ),
              child: const CloudAccountPage(
                entryMode: CloudAccountEntryMode.onboarding,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud_subscription_required')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_subscription_value_props')),
        findsNothing);
    expect(find.textContaining('SecondLoop Pro is required'), findsOneWidget);
    expect(find.textContaining('No Cloudflare'), findsOneWidget);
  });

  testWidgets('Onboarding entitled account calls completion callback',
      (tester) async {
    final auth = _FakeCloudAuthController();
    final subscriptions =
        _FakeSubscriptionStatusController(SubscriptionStatus.entitled);
    var completed = false;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: SubscriptionScope(
            controller: subscriptions,
            child: CloudAuthScope(
              controller: auth,
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.test',
                modelName: 'cloud',
              ),
              child: CloudAccountPage(
                entryMode: CloudAccountEntryMode.onboarding,
                onEntitled: () => completed = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(completed, isTrue);
  });

  testWidgets('Cloud account page can redact signed-in email for screenshots',
      (tester) async {
    final auth = _FakeCloudAuthController(email: 'real-managed@example.com');
    final acceptance = AgentUiAcceptanceController(
      redactedCloudAccountEmail: 'managed-pro-account',
    );
    addTearDown(acceptance.dispose);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AgentUiAcceptanceScope(
            controller: acceptance,
            child: SubscriptionScope(
              controller: _FakeSubscriptionStatusController(
                  SubscriptionStatus.entitled),
              child: CloudAuthScope(
                controller: auth,
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.test',
                  modelName: 'cloud',
                ),
                child: const CloudAccountPage(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('managed-pro-account'), findsOneWidget);
    expect(find.textContaining('real-managed@example.com'), findsNothing);
  });
}

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _FakeCloudAuthController implements CloudAuthController {
  _FakeCloudAuthController({this.email = 'test@example.com'});

  @override
  String? get uid => 'uid_1';

  @override
  final String email;

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'token_1';

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
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

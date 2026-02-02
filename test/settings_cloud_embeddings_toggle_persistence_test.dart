import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/cloud_sync_switch_prompt_gate.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Settings: cloud embeddings toggle does not reset when subscription is unknown',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': true,
    });

    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.unknown);

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: CloudAuthScope(
            controller: cloudAuth,
            child: SubscriptionScope(
              controller: subscription,
              child: wrapWithI18n(
                const MaterialApp(home: Scaffold(body: SettingsPage())),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('embeddings_data_consent_v1'), true);
    expect(find.text('Cloud embeddings'), findsOneWidget);
  });

  testWidgets('Settings: cloud embeddings toggle updates after consent prompt',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);

    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: CloudAuthScope(
            controller: cloudAuth,
            child: SubscriptionScope(
              controller: subscription,
              child: wrapWithI18n(
                MaterialApp(
                  home: CloudSyncSwitchPromptGate(
                    configStore: store,
                    child: const Scaffold(body: SettingsPage()),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, 'Cloud embeddings');
    await tester.dragUntilVisible(
      toggle,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => 'test-id-token';

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

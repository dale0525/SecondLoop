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
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

bool _switchValue(WidgetTester tester, Finder finder) {
  return tester.widget<SwitchListTile>(finder).value;
}

void main() {
  testWidgets(
      'Settings: cloud embeddings preference does not reset when subscription is unknown',
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

    final aiEntry = find.byKey(const ValueKey('settings_ai_source'));
    await tester.dragUntilVisible(
      aiEntry,
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    await tester.tap(aiEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
    final cloudEmbeddingsSwitch =
        find.byKey(const ValueKey('ai_settings_cloud_embeddings_switch'));
    await tester.dragUntilVisible(
      cloudEmbeddingsSwitch,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(_switchValue(tester, cloudEmbeddingsSwitch), isTrue);
  });

  testWidgets(
      'Settings: cloud embeddings prompt updates unified AI settings toggle',
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
    if (find.text('Use cloud for media understanding?').evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();
    }

    final aiEntry = find.byKey(const ValueKey('settings_ai_source'));
    await tester.dragUntilVisible(
      aiEntry,
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    await tester.tap(aiEntry);
    await tester.pumpAndSettle();

    final cloudEmbeddingsSwitch =
        find.byKey(const ValueKey('ai_settings_cloud_embeddings_switch'));
    await tester.dragUntilVisible(
      cloudEmbeddingsSwitch,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(_switchValue(tester, cloudEmbeddingsSwitch), isTrue);
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

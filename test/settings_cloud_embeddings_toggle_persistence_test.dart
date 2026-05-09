import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/embeddings_data_consent_prefs.dart';
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
import 'ai_settings_test_helpers.dart';

void main() {
  testWidgets(
      'Settings: required embeddings capability ignores legacy opt-out when subscription is unknown',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
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
    expect(
      EmbeddingsDataConsentPrefs.readEffectiveEnabled(prefs),
      isTrue,
    );

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
    await openAiAdvancedSettings(tester);
    expect(
      find.byKey(const ValueKey('ai_settings_cloud_embeddings_switch')),
      findsNothing,
    );
  });

  testWidgets('Settings: AI feature guide opens unified AI settings home',
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

    expect(find.byType(AiSettingsPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai_settings_home_smart_organization')),
      findsOneWidget,
    );
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

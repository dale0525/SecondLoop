import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/subscription/creem_billing_client.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/web_app/web_formal_settings_scope.dart';

import 'test_i18n.dart';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntilTaskHubReady(WidgetTester tester) async {
  for (var i = 0; i < 120; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byKey(const ValueKey('task_hub_page')).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  expect(find.byKey(const ValueKey('task_hub_page')), findsOneWidget);
}

void main() {
  testWidgets(
      'TaskHubPage shows base priority content on web without AI enhancement',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    await backend.upsertTodo(
      key,
      id: 'todo:web-base-only',
      title: 'Base-only web task',
      status: 'open',
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: key,
              lock: () {},
              child: const TaskHubPage(),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilTaskHubReady(tester);

    expect(find.byKey(const ValueKey('task_hub_page_item_todo:web-base-only')),
        findsOneWidget);
    expect(find.text('Base-only web task'), findsWidgets);
    expect(
      find.byKey(const ValueKey('task_hub_page_ai_upgrade_hint')),
      findsOneWidget,
    );
  });

  testWidgets('TaskHubPage opens detail page with backend scopes on web',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    await backend.upsertTodo(
      key,
      id: 'todo:task-hub-web',
      title: 'TaskHub web task',
      dueAtMs: DateTime.now().toUtc().millisecondsSinceEpoch + 60000,
      status: 'open',
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: key,
              lock: () {},
              child: const TaskHubPage(),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilTaskHubReady(tester);
    expect(find.byKey(const ValueKey('task_hub_page_item_todo:task-hub-web')),
        findsOneWidget);

    await tester.tap(find.text('TaskHub web task'));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('todo_detail_input')),
    );

    await tester.enterText(
      find.byKey(const ValueKey('todo_detail_input')),
      'task hub web note',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('todo_detail_send')));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('task hub web note'));

    final activities =
        await backend.listTodoActivities(key, 'todo:task-hub-web');
    expect(activities, hasLength(1));
    expect(activities.single.activityType, 'note');
    expect(activities.single.content, 'task hub web note');
  });

  testWidgets(
      'TaskHubPage refreshes AI availability when web subscription becomes entitled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(
        responseText:
            '{"entries":[{"todo_id":"todo:web-entitled","semantic_adjustment":18,"reason":"Cloud prioritizes this task.","confidence":"high","is_important":true,"is_urgent":true}]}',
      ),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    await backend.upsertTodo(
      key,
      id: 'todo:web-entitled',
      title: 'Entitled web task',
      status: 'open',
    );

    final cloudAuth = _FakeCloudAuthController();
    final subscription = _MutableSubscriptionController(
      SubscriptionStatus.unknown,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://web.secondloop.invalid',
                modelName: 'cloud',
              ),
              child: SubscriptionScope(
                controller: subscription,
                child: SessionScope(
                  sessionKey: key,
                  lock: () {},
                  child: const TaskHubPage(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilTaskHubReady(tester);

    expect(
      find.byKey(const ValueKey('task_hub_page_ai_upgrade_hint')),
      findsOneWidget,
    );

    subscription.setStatus(SubscriptionStatus.entitled);
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.text('Cloud prioritizes this task.'),
    );

    expect(
      find.byKey(const ValueKey('task_hub_page_ai_upgrade_hint')),
      findsNothing,
    );
  });

  testWidgets('TaskHubPage hides AI upgrade hint inside web shell',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    await backend.upsertTodo(
      key,
      id: 'todo:web-shell',
      title: 'Web shell task',
      status: 'open',
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: key,
              lock: () {},
              child: WebFormalSettingsScope(
                dependencies: WebFormalSettingsDependencies(
                  billingClient: _FakeBillingClient(),
                  cloudUsageClient: CloudUsageClient(),
                  vaultUsageClient: VaultUsageClient(),
                  vaultAttachmentsClient: VaultAttachmentsClient(),
                  vaultConfigStore: SyncConfigStore(),
                  cloudAuthController: _FakeCloudAuthController(),
                  cloudGatewayConfig: const CloudGatewayConfig(
                    baseUrl: 'https://web.secondloop.invalid',
                    modelName: 'cloud',
                  ),
                  subscriptionController: _MutableSubscriptionController(
                    SubscriptionStatus.entitled,
                  ),
                  isWebOverride: true,
                ),
                child: const TaskHubPage(),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilTaskHubReady(tester);

    expect(
      find.byKey(const ValueKey('task_hub_page_ai_upgrade_hint')),
      findsNothing,
    );
  });
}

final class _FakeCloudWebChatClient implements CloudWebChatClient {
  _FakeCloudWebChatClient({required this.responseText});

  final String responseText;

  @override
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  }) async {
    return responseText;
  }
}

final class _FakeCloudAuthController extends ChangeNotifier
    implements CloudAuthController {
  @override
  String? get uid => 'uid-1';

  @override
  String? get email => 'user@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'token-1';

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

final class _MutableSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _MutableSubscriptionController(this._status);

  SubscriptionStatus _status;

  void setStatus(SubscriptionStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  @override
  SubscriptionStatus get status => _status;
}

final class _FakeBillingClient implements BillingClient {
  @override
  Future<void> openCheckout() async {}

  @override
  Future<void> openPortal() async {}
}

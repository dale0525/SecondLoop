import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/web_app/web_chat_page.dart';
import 'package:secondloop/web_app/web_app_service.dart';
import 'package:secondloop/web_app/web_formal_settings_adapters.dart';

import '../test_i18n.dart';

void main() {
  testWidgets('failed web chat keeps the user message visible', (tester) async {
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(
        error:
            'cloud-gateway request failed: HTTP 429 {"error":"rate_limited"}',
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: WebChatPage(
              service: _FakeWebAppService(),
              authController: _FakeCloudAuthController(),
              chatBackend: backend,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello from the browser');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.text('Hello from the browser'), findsOneWidget);
    expect(find.text('Cloud is rate limited. Please try again later.'),
        findsOneWidget);
  });

  testWidgets('web chat forwards formal gateway config to cloud backend',
      (tester) async {
    final client = _FakeCloudWebChatClient();
    final backend = CloudWebBackend(chatClient: client);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: WebChatPage(
              service: _FakeWebAppService(),
              authController: _FakeCloudAuthController(),
              chatBackend: backend,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello config');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(client.lastGatewayBaseUrl, kWebFormalSettingsBaseUrl);
    expect(client.lastModelName, 'cloud');
  });

  testWidgets('web chat surfaces auth expiry inline when token is unavailable',
      (tester) async {
    final backend = CloudWebBackend(chatClient: _FakeCloudWebChatClient());
    final authController = _FakeCloudAuthController();
    authController.deferNextIdToken();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: WebChatPage(
              service: _FakeWebAppService(),
              authController: authController,
              chatBackend: backend,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello expired');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();

    authController.completeDeferredIdToken(null);
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Cloud sign-in required. Open Cloud account and sign in again.'),
      findsOneWidget,
    );
    expect(find.text('Hello expired'), findsOneWidget);
  });

  testWidgets('web chat ignores rapid double tap before auth resolves',
      (tester) async {
    final client = _FakeCloudWebChatClient();
    final backend = CloudWebBackend(chatClient: client);
    final authController = _FakeCloudAuthController();
    authController.deferNextIdToken();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: WebChatPage(
              service: _FakeWebAppService(),
              authController: authController,
              chatBackend: backend,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello once');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();

    authController.completeDeferredIdToken('token-1');
    await tester.pumpAndSettle();

    expect(client.sendCallCount, 1);
    expect(find.text('Hello once'), findsOneWidget);
  });
}

final class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  Completer<String?>? _deferredIdToken;

  @override
  String? get uid => 'uid-1';

  @override
  String? get email => 'user@example.com';

  @override
  bool? get emailVerified => true;

  void deferNextIdToken() {
    _deferredIdToken = Completer<String?>();
  }

  void completeDeferredIdToken(String? value) {
    _deferredIdToken?.complete(value);
    _deferredIdToken = null;
  }

  @override
  Future<String?> getIdToken() async {
    final deferredIdToken = _deferredIdToken;
    if (deferredIdToken != null) return deferredIdToken.future;
    return 'token-1';
  }

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<void> signInWithEmailPassword(
      {required String email, required String password}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword(
      {required String email, required String password}) async {}
}

final class _FakeCloudWebChatClient implements CloudWebChatClient {
  _FakeCloudWebChatClient({this.error});

  final Object? error;
  String? lastGatewayBaseUrl;
  String? lastModelName;
  int sendCallCount = 0;

  @override
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  }) async {
    sendCallCount += 1;
    lastGatewayBaseUrl = gatewayBaseUrl;
    lastModelName = modelName;
    if (error != null) throw error!;
    return 'ok';
  }
}

final class _FakeWebAppService extends WebAppService {
  @override
  Future<WebSubscriptionSnapshot> fetchSubscription(
          {required String idToken}) async =>
      const WebSubscriptionSnapshot(
        state: WebSubscriptionState.entitled,
        canManageSubscription: true,
      );
}

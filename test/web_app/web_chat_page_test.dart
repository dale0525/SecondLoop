import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/web_app/web_chat_page.dart';
import 'package:secondloop/web_app/web_app_service.dart';

import '../test_i18n.dart';

void main() {
  testWidgets('failed web chat keeps the user message visible', (tester) async {
    final backend = CloudWebBackend(
      chatClient: const _FakeCloudWebChatClient(
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
}

final class _FakeCloudAuthController extends ChangeNotifier
    implements CloudAuthController, CloudPasswordRecoveryController {
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
  const _FakeCloudWebChatClient({this.error});

  final Object? error;

  @override
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  }) async {
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

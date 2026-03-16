import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/web_app/web_app_gate.dart';

import '../test_i18n.dart';

class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  _FakeCloudAuthController({
    this.initialUid,
    this.initialEmail,
    this.initialEmailVerified,
  })  : _uid = initialUid,
        _email = initialEmail,
        _emailVerified = initialEmailVerified;

  final String? initialUid;
  final String? initialEmail;
  final bool? initialEmailVerified;

  final String? _uid;
  final String? _email;
  final bool? _emailVerified;

  @override
  String? get uid => _uid;

  @override
  String? get email => _email;

  @override
  bool? get emailVerified => _emailVerified;

  @override
  Future<String?> getIdToken() async => _uid == null ? null : 'token';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword(
      {required String email, required String password}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword(
      {required String email, required String password}) async {}

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}
}

final class _FakeWebAppService extends WebAppService {
  _FakeWebAppService({required this.items});

  final List<WebVaultAttachmentItem> items;

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription(
          {required String idToken}) async =>
      const WebSubscriptionSnapshot(
        state: WebSubscriptionState.entitled,
        canManageSubscription: true,
      );

  @override
  Future<WebVaultUsageSummary?> fetchVaultUsage({
    required String idToken,
    required String vaultId,
  }) async {
    return const WebVaultUsageSummary(totalBytesUsed: 1024, limitBytes: 2048);
  }

  @override
  Future<List<WebVaultAttachmentItem>> listVaultAttachments({
    required String idToken,
    required String vaultId,
  }) async =>
      items;
}

Widget _buildApp(List<WebVaultAttachmentItem> items) {
  return wrapWithI18n(
    MaterialApp(
      home: WebAppGate(
        authController: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(items: items),
      ),
    ),
  );
}

void main() {
  testWidgets('complex media shows readonly continue-in-app notice',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(const [
        WebVaultAttachmentItem(
          sha256: 'video-sha',
          mimeType: 'video/mp4',
          byteLen: 4096,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('Continue processing in the app'), findsOneWidget);
    expect(
      find.textContaining('Existing cloud results stay available here'),
      findsOneWidget,
    );
  });

  testWidgets('web-safe media does not show continue-in-app notice',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(const [
        WebVaultAttachmentItem(
          sha256: 'image-sha',
          mimeType: 'image/png',
          byteLen: 1024,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('Continue processing in the app'), findsNothing);
  });

  testWidgets('grouped video also shows readonly continue-in-app notice',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(const [
        WebVaultAttachmentItem(
          sha256: 'group-leaf-sha',
          rootSha256: 'group-root-sha',
          groupType: 'video',
          mimeType: 'application/octet-stream',
          byteLen: 2048,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('Continue processing in the app'), findsOneWidget);
  });
}

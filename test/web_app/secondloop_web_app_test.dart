import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/i18n/locale_prefs.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/web_app/secondloop_web_app.dart';
import 'package:secondloop/web_app/web_app_service.dart';
import 'package:secondloop/features/settings/cloud_account_panel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleBootstrap.resetForTests();
    LocaleSettings.setLocale(AppLocale.en);
  });

  test('parseWebEntryIntent normalizes known and unknown query values', () {
    expect(
      parseWebEntryIntent(Uri.parse('https://secondloop.app/app?intent=open')),
      WebEntryIntent.open,
    );
    expect(
      parseWebEntryIntent(
        Uri.parse('https://secondloop.app/app?intent=subscribe'),
      ),
      WebEntryIntent.subscribe,
    );
    expect(
      parseWebEntryIntent(
          Uri.parse('https://secondloop.app/app?intent=manage')),
      WebEntryIntent.manage,
    );
    expect(
      parseWebEntryIntent(Uri.parse('https://secondloop.app/app?intent=else')),
      WebEntryIntent.open,
    );
  });

  testWidgets('web app localizes bootstrap failure in zh-CN', (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);

    await tester.pumpWidget(
      SecondLoopWebApp(
        bootstrapLoader: () async => throw StateError('config_http_500'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Web 应用启动失败：'), findsOneWidget);
    expect(find.textContaining('config_http_500'), findsOneWidget);
  });

  testWidgets('web app follows device locale on first launch', (tester) async {
    tester.binding.platformDispatcher.localeTestValue =
        const Locale('zh', 'CN');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(
      SecondLoopWebApp(
        bootstrapLoader: () async => throw StateError('config_http_500'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Web 应用启动失败：'), findsOneWidget);
    expect(find.textContaining('config_http_500'), findsOneWidget);
  });

  testWidgets(
      'web app keeps gate reachable when refreshUserInfo fails during bootstrap',
      (tester) async {
    await tester.pumpWidget(
      SecondLoopWebApp(
        configLoader: () async =>
            const WebAppConfig(firebaseWebApiKey: 'firebase-key'),
        serviceFactory: () => _FakeWebAppService(),
        authControllerFactory: (config) => _FakeCloudAuthController(
          refreshError: StateError('lookup_failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to start Web app:'), findsNothing);
    expect(find.byType(CloudAccountPanel), findsOneWidget);
  });

  testWidgets('web app disposes bootstrapped service on teardown',
      (tester) async {
    final service = _DisposableFakeWebAppService();

    await tester.pumpWidget(
      SecondLoopWebApp(
        configLoader: () async =>
            const WebAppConfig(firebaseWebApiKey: 'firebase-key'),
        serviceFactory: () => service,
        authControllerFactory: (config) => _FakeCloudAuthController(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(service.closeCount, 1);
  });
}

final class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  _FakeCloudAuthController({this.refreshError});

  final Object? refreshError;
  int disposeCount = 0;

  @override
  String? get uid => null;

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => null;

  @override
  Future<void> refreshUserInfo() async {
    if (refreshError != null) throw refreshError!;
  }

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

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

  @override
  void dispose() {
    disposeCount += 1;
    super.dispose();
  }
}

class _FakeWebAppService extends WebAppService {
  @override
  Future<WebSubscriptionSnapshot> fetchSubscription(
          {required String idToken}) async =>
      const WebSubscriptionSnapshot(
        state: WebSubscriptionState.unknown,
        canManageSubscription: null,
      );
}

final class _DisposableFakeWebAppService extends _FakeWebAppService {
  int closeCount = 0;

  @override
  void close() {
    closeCount += 1;
  }
}

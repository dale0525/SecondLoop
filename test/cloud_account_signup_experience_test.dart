import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    LocaleSettings.setLocale(AppLocale.en);
  });

  testWidgets('sign up shows localized verify-email reminder in English',
      (tester) async {
    final cloudAuth = _MutableCloudAuthController();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            child: const CloudAccountPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'new-user@example.com',
    );
    await tester.enterText(find.byType(TextField).last, 'password123');
    final signUpButton = find.byKey(const ValueKey('cloud_sign_up')).first;
    await tester.drag(find.byType(ListView).first, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(signUpButton);
    await tester.pumpAndSettle();

    expect(cloudAuth.signUpCalls, 1);
    expect(cloudAuth.sendEmailVerificationCalls, 1);
    expect(
      find.text(
          'Account created. Please verify your email before subscribing.'),
      findsWidgets,
    );
  });

  testWidgets('sign up reminder follows app locale (zh-CN)', (tester) async {
    final cloudAuth = _MutableCloudAuthController();

    LocaleSettings.setLocale(AppLocale.zhCn);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            child: const CloudAccountPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).first, 'new-user@example.com');
    await tester.enterText(find.byType(TextField).last, 'password123');
    final signUpButton = find.byKey(const ValueKey('cloud_sign_up')).first;
    await tester.drag(find.byType(ListView).first, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(signUpButton);
    await tester.pumpAndSettle();

    expect(
      find.text('账号已创建，请先完成邮箱验证再进行订阅。'),
      findsWidgets,
    );
  });

  testWidgets(
      'resend verification handles already-verified response gracefully',
      (tester) async {
    final cloudAuth = _MutableCloudAuthController(
      initialUid: 'uid_1',
      initialEmail: 'test@example.com',
      initialEmailVerified: false,
      sendVerificationError: FirebaseAuthException('EMAIL_ALREADY_VERIFIED'),
      verifyAfterSendError: true,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            child: const CloudAccountPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud_resend_verification')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cloud_resend_verification')));
    await tester.pumpAndSettle();

    expect(cloudAuth.sendEmailVerificationCalls, 1);
    expect(
        find.byKey(const ValueKey('cloud_resend_verification')), findsNothing);
    expect(find.text('Email is already verified.'), findsOneWidget);
    expect(
        find.textContaining('Failed to send verification email'), findsNothing);
    expect(find.text('Email is verified. You can continue to subscribe.'),
        findsOneWidget);
  });
}

final class _MutableCloudAuthController implements CloudAuthController {
  _MutableCloudAuthController({
    String? initialUid,
    String? initialEmail,
    bool? initialEmailVerified,
    this.sendVerificationError,
    this.verifyAfterSendError = false,
  })  : _uid = initialUid,
        _email = initialEmail,
        _emailVerified = initialEmailVerified;

  String? _uid;
  String? _email;
  bool? _emailVerified;

  final Object? sendVerificationError;
  final bool verifyAfterSendError;

  bool _verifyOnNextRefresh = false;

  int signUpCalls = 0;
  int sendEmailVerificationCalls = 0;

  @override
  String? get uid => _uid;

  @override
  String? get email => _email;

  @override
  bool? get emailVerified => _emailVerified;

  @override
  Future<String?> getIdToken() async => 'token_1';

  @override
  Future<void> refreshUserInfo() async {
    if (_verifyOnNextRefresh) {
      _emailVerified = true;
      _verifyOnNextRefresh = false;
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    sendEmailVerificationCalls += 1;
    if (sendVerificationError != null) {
      if (verifyAfterSendError) {
        _verifyOnNextRefresh = true;
      }
      throw sendVerificationError!;
    }
  }

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _uid = 'uid_1';
    _email = email;
    _emailVerified = false;
  }

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    signUpCalls += 1;
    _uid = 'uid_1';
    _email = email;
    _emailVerified = false;
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _email = null;
    _emailVerified = null;
  }
}

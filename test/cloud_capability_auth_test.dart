import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_store.dart';
import 'package:secondloop/core/cloud/cloud_capability_auth.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';

void main() {
  test('interactive cloud capability token loads persisted session', () async {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previous;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final toolkit = _RefreshingIdentityToolkit();
    final store = _InMemoryCloudAuthStore(
      const CloudAuthStoredSession(uid: 'uid_1', refreshToken: 'refresh_1'),
    );
    final controller = CloudAuthControllerImpl(
      identityToolkit: toolkit,
      store: store,
      nowMs: () => 1000,
    );

    final token = await readCloudCapabilityIdToken(
      controller,
      mode: CloudCapabilityAuthMode.interactive,
    );

    expect(token, 'id_token_1');
    expect(store.loadCalls, 1);
    expect(toolkit.refreshCalls, 1);
  });

  test('background cloud capability token keeps persisted session untouched',
      () async {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previous;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final toolkit = _RefreshingIdentityToolkit();
    final store = _InMemoryCloudAuthStore(
      const CloudAuthStoredSession(uid: 'uid_1', refreshToken: 'refresh_1'),
    );
    final controller = CloudAuthControllerImpl(
      identityToolkit: toolkit,
      store: store,
      nowMs: () => 1000,
    );

    final token = await readCloudCapabilityIdToken(
      controller,
      mode: CloudCapabilityAuthMode.background,
    );

    expect(token, isNull);
    expect(store.loadCalls, 0);
    expect(toolkit.refreshCalls, 0);
  });

  test('best-effort warm uses interactive token path', () async {
    final controller = _FakeCloudAuthController();

    await bestEffortWarmCloudCapabilityAuth(controller);

    expect(controller.getIdTokenCalls, 1);
  });
}

final class _InMemoryCloudAuthStore implements CloudAuthStore {
  _InMemoryCloudAuthStore([this._session]);

  CloudAuthStoredSession? _session;
  int loadCalls = 0;

  @override
  Future<CloudAuthStoredSession?> load() async {
    loadCalls += 1;
    return _session;
  }

  @override
  Future<void> save(CloudAuthStoredSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

final class _RefreshingIdentityToolkit implements FirebaseIdentityToolkit {
  int refreshCalls = 0;

  @override
  Future<FirebaseAuthTokens> refreshIdToken(
      {required String refreshToken}) async {
    refreshCalls += 1;
    if (refreshToken != 'refresh_1') {
      throw StateError('unexpected_refresh_token');
    }
    return const FirebaseAuthTokens(
      idToken: 'id_token_1',
      refreshToken: 'refresh_1',
      uid: 'uid_1',
      expiresAtMs: 1 << 30,
    );
  }

  @override
  Future<FirebaseAuthTokens> signInWithPassword({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FirebaseAuthTokens> signUpWithPassword({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FirebaseUserInfo> lookup({required String idToken}) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendOobCode({
    required String requestType,
    String? idToken,
    String? email,
  }) {
    throw UnimplementedError();
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  int getIdTokenCalls = 0;

  @override
  String? get uid => 'uid_1';

  @override
  String? get email => 'test@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async {
    getIdTokenCalls += 1;
    return 'token';
  }

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

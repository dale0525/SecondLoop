import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_store.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';

void main() {
  test('CloudAuthController caches idToken and refreshes when expired',
      () async {
    final clock = _FakeClockMs(1000);
    final toolkit = _FakeIdentityToolkit(clock: clock);
    final store = _InMemoryCloudAuthStore();

    final controller = CloudAuthControllerImpl(
      identityToolkit: toolkit,
      store: store,
      nowMs: clock.nowMs,
    );

    await controller.signInWithEmailPassword(
      email: 'test@example.com',
      password: 'pw',
    );

    expect(await controller.getIdToken(), 'id_token_1');
    expect(toolkit.signInCalls, 1);
    expect(toolkit.refreshCalls, 0);

    clock.advance(5000);
    expect(await controller.getIdToken(), 'id_token_1');
    expect(toolkit.refreshCalls, 0);

    clock.advance(10000);
    expect(await controller.getIdToken(), 'id_token_2');
    expect(toolkit.refreshCalls, 1);
  });
}

final class _FakeClockMs {
  _FakeClockMs(this._nowMs);

  int _nowMs;

  int nowMs() => _nowMs;

  void advance(int deltaMs) {
    _nowMs += deltaMs;
  }
}

final class _FakeIdentityToolkit implements FirebaseIdentityToolkit {
  _FakeIdentityToolkit({required this.clock});

  final _FakeClockMs clock;

  int signInCalls = 0;
  int refreshCalls = 0;

  @override
  Future<FirebaseAuthTokens> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalls += 1;
    return FirebaseAuthTokens(
      idToken: 'id_token_1',
      refreshToken: 'refresh_1',
      uid: 'uid_1',
      expiresAtMs: clock.nowMs() + 10000,
    );
  }

  @override
  Future<FirebaseAuthTokens> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<FirebaseAuthTokens> refreshIdToken(
      {required String refreshToken}) async {
    refreshCalls += 1;
    return FirebaseAuthTokens(
      idToken: 'id_token_2',
      refreshToken: 'refresh_2',
      uid: 'uid_1',
      expiresAtMs: clock.nowMs() + 10000,
    );
  }

  @override
  Future<void> sendOobCode({
    required String requestType,
    required String idToken,
  }) async {}

  @override
  Future<FirebaseUserInfo> lookup({required String idToken}) async {
    return const FirebaseUserInfo(email: null, emailVerified: null);
  }
}

final class _InMemoryCloudAuthStore implements CloudAuthStore {
  CloudAuthStoredSession? _session;

  @override
  Future<CloudAuthStoredSession?> load() async => _session;

  @override
  Future<void> save(CloudAuthStoredSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

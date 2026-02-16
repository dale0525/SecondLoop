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

  test('refreshUserInfo invalidates cached token after email becomes verified',
      () async {
    final clock = _FakeClockMs(1000);
    final toolkit = _FakeIdentityToolkit(
      clock: clock,
      lookupResponses: const <FirebaseUserInfo>[
        FirebaseUserInfo(email: 'test@example.com', emailVerified: false),
        FirebaseUserInfo(email: 'test@example.com', emailVerified: true),
      ],
    );
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
    expect(toolkit.refreshCalls, 0);

    await controller.refreshUserInfo();
    expect(controller.emailVerified, isFalse);
    expect(await controller.getIdToken(), 'id_token_1');
    expect(toolkit.refreshCalls, 0);

    await controller.refreshUserInfo();
    expect(controller.emailVerified, isTrue);
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
  _FakeIdentityToolkit({
    required this.clock,
    List<FirebaseUserInfo>? lookupResponses,
  }) : _lookupResponses = lookupResponses ??
            const <FirebaseUserInfo>[
              FirebaseUserInfo(email: null, emailVerified: null),
            ];

  final _FakeClockMs clock;
  final List<FirebaseUserInfo> _lookupResponses;

  int signInCalls = 0;
  int refreshCalls = 0;
  int lookupCalls = 0;

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
    final index = lookupCalls;
    lookupCalls += 1;

    if (index >= _lookupResponses.length) {
      return _lookupResponses.last;
    }
    return _lookupResponses[index];
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

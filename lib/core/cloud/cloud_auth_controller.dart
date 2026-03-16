import 'package:flutter/foundation.dart';

import 'cloud_auth_store.dart';
import 'firebase_identity_toolkit.dart';

abstract class CloudAuthController {
  String? get uid;

  String? get email;

  bool? get emailVerified;

  Future<String?> getIdToken();

  Future<void> refreshUserInfo();

  Future<void> sendEmailVerification();

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  });

  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

abstract class ObservableCloudAuthController
    implements CloudAuthController, Listenable {}

abstract class CloudPasswordRecoveryController {
  Future<void> sendPasswordResetEmail({
    required String email,
  });
}

Future<void> sendCloudPasswordResetEmail({
  required CloudAuthController controller,
  required String email,
}) async {
  if (controller is! CloudPasswordRecoveryController) {
    throw StateError('password_reset_not_supported');
  }
  final recoveryController = controller as CloudPasswordRecoveryController;
  await recoveryController.sendPasswordResetEmail(email: email);
}

Future<String?> readCloudIdTokenForBackground(CloudAuthController? controller) {
  if (controller == null) {
    return Future<String?>.value();
  }
  if (controller case final CloudAuthControllerImpl impl) {
    return impl.getIdTokenSilently();
  }
  return controller.getIdToken();
}

final class CloudAuthControllerImpl extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  CloudAuthControllerImpl({
    required FirebaseIdentityToolkit identityToolkit,
    CloudAuthStore? store,
    int Function()? nowMs,
  })  : _identityToolkit = identityToolkit,
        _store = store ?? createDefaultCloudAuthStore(),
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final FirebaseIdentityToolkit _identityToolkit;
  final CloudAuthStore _store;
  final int Function() _nowMs;

  bool _loaded = false;
  CloudAuthStoredSession? _storedSession;
  FirebaseAuthTokens? _cachedTokens;
  FirebaseUserInfo? _cachedUserInfo;

  @override
  String? get uid => _storedSession?.uid ?? _cachedTokens?.uid;

  @override
  String? get email => _cachedUserInfo?.email;

  @override
  bool? get emailVerified => _cachedUserInfo?.emailVerified;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _storedSession = await _store.load();
    _loaded = true;
  }

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final tokens = await _identityToolkit.signInWithPassword(
      email: email,
      password: password,
    );
    _cachedTokens = tokens;
    _cachedUserInfo = null;
    _storedSession = CloudAuthStoredSession(
        uid: tokens.uid, refreshToken: tokens.refreshToken);
    _loaded = true;
    await _store.save(_storedSession!);
    notifyListeners();
  }

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final tokens = await _identityToolkit.signUpWithPassword(
      email: email,
      password: password,
    );
    _cachedTokens = tokens;
    _cachedUserInfo = null;
    _storedSession = CloudAuthStoredSession(
        uid: tokens.uid, refreshToken: tokens.refreshToken);
    _loaded = true;
    await _store.save(_storedSession!);
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _cachedTokens = null;
    _cachedUserInfo = null;
    _storedSession = null;
    _loaded = true;
    await _store.clear();
    notifyListeners();
  }

  @override
  Future<String?> getIdToken() async {
    return _getIdToken();
  }

  Future<String?> getIdTokenSilently() async {
    final cached = _cachedTokens;
    if (cached == null) return null;
    if (_nowMs() >= cached.expiresAtMs) return null;
    return cached.idToken;
  }

  Future<String?> _getIdToken({bool forceRefresh = false}) async {
    await _ensureLoaded();
    final cached = _cachedTokens;
    if (!forceRefresh && cached != null && _nowMs() < cached.expiresAtMs) {
      return cached.idToken;
    }

    final stored = _storedSession;
    if (stored == null) return null;

    final refreshed = await _identityToolkit.refreshIdToken(
        refreshToken: stored.refreshToken);
    _cachedTokens = refreshed;
    _storedSession = CloudAuthStoredSession(
      uid: refreshed.uid,
      refreshToken: refreshed.refreshToken,
    );
    await _store.save(_storedSession!);
    notifyListeners();
    return refreshed.idToken;
  }

  @override
  Future<void> refreshUserInfo() async {
    final token = await _getIdToken();
    if (token == null || token.trim().isEmpty) {
      if (_cachedUserInfo == null) return;
      _cachedUserInfo = null;
      notifyListeners();
      return;
    }

    final previousEmailVerified = _cachedUserInfo?.emailVerified;
    final info = await _identityToolkit.lookup(idToken: token);
    _cachedUserInfo = info;

    if (previousEmailVerified == false && info.emailVerified == true) {
      // Force a token refresh on the next authenticated call so backend checks
      // immediately observe the verified-email state.
      _cachedTokens = null;
    }

    notifyListeners();
  }

  @override
  Future<void> sendEmailVerification() async {
    Future<void> sendWithToken({required bool forceRefresh}) async {
      final token = await _getIdToken(forceRefresh: forceRefresh);
      if (token == null || token.trim().isEmpty) {
        throw StateError('missing_id_token');
      }

      await _identityToolkit.sendOobCode(
        requestType: 'VERIFY_EMAIL',
        idToken: token,
      );
    }

    try {
      await sendWithToken(forceRefresh: false);
    } catch (error) {
      if (!_shouldRetryEmailVerification(error)) rethrow;
      await sendWithToken(forceRefresh: true);
    }
  }

  static bool _shouldRetryEmailVerification(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('missing_id_token') ||
        normalized.contains('invalid_id_token') ||
        normalized.contains('token_expired');
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
  }) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw StateError('missing_email');
    }
    await _identityToolkit.sendOobCode(
      requestType: 'PASSWORD_RESET',
      email: normalizedEmail,
    );
  }
}

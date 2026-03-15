import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

@immutable
class FirebaseAuthTokens {
  const FirebaseAuthTokens({
    required this.idToken,
    required this.refreshToken,
    required this.uid,
    required this.expiresAtMs,
  });

  final String idToken;
  final String refreshToken;
  final String uid;
  final int expiresAtMs;
}

@immutable
class FirebaseUserInfo {
  const FirebaseUserInfo({
    required this.email,
    required this.emailVerified,
  });

  final String? email;
  final bool? emailVerified;
}

class FirebaseAuthException implements Exception {
  FirebaseAuthException(this.code, {this.details});

  final String code;
  final String? details;

  @override
  String toString() {
    if (details == null || details!.trim().isEmpty) return code;
    return '$code: $details';
  }
}

abstract class FirebaseIdentityToolkit {
  Future<FirebaseAuthTokens> signInWithPassword({
    required String email,
    required String password,
  });

  Future<FirebaseAuthTokens> signUpWithPassword({
    required String email,
    required String password,
  });

  Future<FirebaseAuthTokens> refreshIdToken({
    required String refreshToken,
  });

  Future<void> sendOobCode({
    required String requestType,
    String? idToken,
    String? email,
  });

  Future<FirebaseUserInfo> lookup({
    required String idToken,
  });
}

final class FirebaseIdentityToolkitHttp implements FirebaseIdentityToolkit {
  FirebaseIdentityToolkitHttp({
    required this.webApiKey,
    http.Client? httpClient,
    int Function()? nowMs,
  })  : _httpClient = httpClient ?? http.Client(),
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String webApiKey;
  final http.Client _httpClient;
  final int Function() _nowMs;

  Uri _accountsUri(String method) {
    return Uri.https(
      'identitytoolkit.googleapis.com',
      '/v1/accounts:$method',
      {'key': webApiKey},
    );
  }

  Uri _tokenUri() {
    return Uri.https(
      'securetoken.googleapis.com',
      '/v1/token',
      {'key': webApiKey},
    );
  }

  @override
  Future<FirebaseAuthTokens> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final body = await _postJson(
      _accountsUri('signInWithPassword'),
      {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      },
    );
    return _parseAccountsResponse(body);
  }

  @override
  Future<FirebaseAuthTokens> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final body = await _postJson(
      _accountsUri('signUp'),
      {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      },
    );
    return _parseAccountsResponse(body);
  }

  @override
  Future<FirebaseAuthTokens> refreshIdToken({
    required String refreshToken,
  }) async {
    final body = await _postForm(
      _tokenUri(),
      {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    final idToken = body['id_token'];
    final nextRefreshToken = body['refresh_token'];
    final uid = body['user_id'];
    final expiresIn = body['expires_in'];

    if (idToken is! String || idToken.trim().isEmpty) {
      throw FirebaseAuthException('missing_id_token');
    }
    if (nextRefreshToken is! String || nextRefreshToken.trim().isEmpty) {
      throw FirebaseAuthException('missing_refresh_token');
    }
    if (uid is! String || uid.trim().isEmpty) {
      throw FirebaseAuthException('missing_user_id');
    }

    final expiresInSec = expiresIn is String ? int.tryParse(expiresIn) : null;
    final expiresAtMs = _nowMs() + (expiresInSec ?? 3600) * 1000;

    return FirebaseAuthTokens(
      idToken: idToken,
      refreshToken: nextRefreshToken,
      uid: uid,
      expiresAtMs: expiresAtMs,
    );
  }

  @override
  Future<void> sendOobCode({
    required String requestType,
    String? idToken,
    String? email,
  }) async {
    final payload = <String, dynamic>{
      'requestType': requestType,
    };
    final normalizedToken = idToken?.trim();
    if (normalizedToken != null && normalizedToken.isNotEmpty) {
      payload['idToken'] = normalizedToken;
    }
    final normalizedEmail = email?.trim();
    if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
      payload['email'] = normalizedEmail;
    }
    await _postJson(_accountsUri('sendOobCode'), payload);
  }

  @override
  Future<FirebaseUserInfo> lookup({required String idToken}) async {
    final body = await _postJson(
      _accountsUri('lookup'),
      {'idToken': idToken},
    );

    final users = body['users'];
    if (users is List && users.isNotEmpty) {
      final first = users.first;
      if (first is Map) {
        final email = first['email'];
        final emailVerified = first['emailVerified'];
        return FirebaseUserInfo(
          email: email is String && email.trim().isNotEmpty ? email : null,
          emailVerified: emailVerified is bool ? emailVerified : null,
        );
      }
    }

    throw FirebaseAuthException('missing_user');
  }

  FirebaseAuthTokens _parseAccountsResponse(Map<String, dynamic> body) {
    final idToken = body['idToken'];
    final refreshToken = body['refreshToken'];
    final uid = body['localId'];
    final expiresIn = body['expiresIn'];

    if (idToken is! String || idToken.trim().isEmpty) {
      throw FirebaseAuthException('missing_id_token');
    }
    if (refreshToken is! String || refreshToken.trim().isEmpty) {
      throw FirebaseAuthException('missing_refresh_token');
    }
    if (uid is! String || uid.trim().isEmpty) {
      throw FirebaseAuthException('missing_local_id');
    }

    final expiresInSec = expiresIn is String ? int.tryParse(expiresIn) : null;
    final expiresAtMs = _nowMs() + (expiresInSec ?? 3600) * 1000;

    return FirebaseAuthTokens(
      idToken: idToken,
      refreshToken: refreshToken,
      uid: uid,
      expiresAtMs: expiresAtMs,
    );
  }

  Future<Map<String, dynamic>> _postJson(
    Uri url,
    Map<String, dynamic> payload,
  ) async {
    if (webApiKey.trim().isEmpty) {
      throw FirebaseAuthException('missing_web_api_key');
    }

    final response = await _httpClient.post(
      url,
      headers: const <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(payload),
    );
    final decoded = _tryJsonDecodeObject(response.body) ?? <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirebaseAuthException(
        _extractErrorCode(decoded) ?? 'http_${response.statusCode}',
        details: _extractErrorMessage(decoded),
      );
    }

    return decoded;
  }

  Future<Map<String, dynamic>> _postForm(
    Uri url,
    Map<String, String> form,
  ) async {
    if (webApiKey.trim().isEmpty) {
      throw FirebaseAuthException('missing_web_api_key');
    }

    final response = await _httpClient.post(
      url,
      headers: const <String, String>{
        'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
        'accept': 'application/json',
      },
      body: form,
    );
    final decoded = _tryJsonDecodeObject(response.body) ?? <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirebaseAuthException(
        _extractErrorCode(decoded) ?? 'http_${response.statusCode}',
        details: _extractErrorMessage(decoded),
      );
    }

    return decoded;
  }

  static Map<String, dynamic>? _tryJsonDecodeObject(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _extractErrorCode(Map<String, dynamic> decoded) {
    final error = decoded['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    if (error is String && error.trim().isNotEmpty) return error;
    return null;
  }

  static String? _extractErrorMessage(Map<String, dynamic> decoded) {
    final error = decoded['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    return null;
  }
}

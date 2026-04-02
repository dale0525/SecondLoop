import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';

void main() {
  test('warns when latest.json signature verification is skipped', () async {
    final requestedUris = <Uri>[];
    final originalDebugPrint = debugPrint;
    final messages = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        messages.add(message);
      }
    };
    addTearDown(() {
      debugPrint = originalDebugPrint;
    });

    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        handler: (uri) {
          requestedUris.add(uri);
          if (uri.path.endsWith('latest.json')) {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'version': '1.1.0',
                'release_page_url':
                    'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
                'platforms': {
                  'linux-x64': {
                    'install_mode': 'bundle-tar-gz',
                    'archive_url':
                        'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
                    'sha256': 'abc123',
                  },
                },
              }),
            );
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseRepoOverride: 'dale0525/SecondLoop',
      updatePublicKeyOverride: '',
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNotNull);
    expect(requestedUris, hasLength(1));
    expect(requestedUris.single.path, endsWith('latest.json'));
    expect(
      messages,
      contains(
        contains('SECONDLOOP_UPDATE_PUBLIC_KEY is not set'),
      ),
    );
  });

  test('times out when latest.json signature fetch stalls', () async {
    final requestedUris = <Uri>[];
    final stalledRequest = Completer<HttpClientRequest>();
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        onGetUrl: (uri) async {
          requestedUris.add(uri);
          if (uri.path.endsWith('latest.json')) {
            return _FakeHttpClientRequest(
              response: _FakeHttpClientResponse(
                statusCode: 200,
                body: jsonEncode({
                  'version': '1.1.0',
                  'release_page_url':
                      'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
                  'platforms': {
                    'linux-x64': {
                      'install_mode': 'bundle-tar-gz',
                      'archive_url':
                          'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
                      'sha256': 'abc123',
                    },
                  },
                }),
              ),
            );
          }
          if (uri.path.endsWith('latest.json.sig') ||
              uri.path.endsWith('/releases/latest')) {
            return stalledRequest.future;
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseRepoOverride: 'dale0525/SecondLoop',
      updatePublicKeyOverride: base64Encode(List<int>.generate(32, (i) => i)),
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
      networkTimeoutOverride: const Duration(milliseconds: 10),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNull);
    expect(result.errorMessage, contains('TimeoutException'));
    final requestedPaths = requestedUris.map((uri) => uri.path).toList();
    expect(
      requestedPaths,
      contains('/dale0525/SecondLoop/releases/latest/download/latest.json'),
    );
    expect(
      requestedPaths,
      contains('/dale0525/SecondLoop/releases/latest/download/latest.json.sig'),
    );
  });

  test('verifies signature for custom api latest endpoint', () async {
    final requestedUris = <Uri>[];
    final seed = List<int>.generate(32, (index) => index + 11);
    final manifestBody = jsonEncode({
      'version': '1.1.0',
      'release_page_url': 'https://updates.example.com/releases/v1.1.0',
      'platforms': {
        'linux-x64': {
          'install_mode': 'bundle-tar-gz',
          'archive_url':
              'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
          'sha256': 'abc123',
        },
      },
    });
    final signatureBase64 = await _signEd25519Base64(
      payload: utf8.encode(manifestBody),
      seed: seed,
    );
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        handler: (uri) {
          requestedUris.add(uri);
          if (uri.path.endsWith('/api/releases/latest')) {
            return _FakeHttpResponse(
              statusCode: 200,
              body: manifestBody,
            );
          }
          if (uri.path.endsWith('/api/releases/latest.sig')) {
            return _FakeHttpResponse(
              statusCode: 200,
              body: signatureBase64,
            );
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseApiOriginOverride: 'https://updates.example.com/custom/base',
      releaseRepoOverride: '',
      updatePublicKeyOverride: await _ed25519PublicKeyBase64FromSeed(seed),
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.errorMessage, isNull);
    expect(result.update, isNotNull);
    final requestedPaths = requestedUris.map((uri) => uri.path).toList();
    expect(requestedPaths, contains('/custom/base/api/releases/latest'));
    expect(
      requestedPaths,
      contains('/custom/base/api/releases/latest.sig'),
    );
  });

  test('fails when custom api latest signature is missing', () async {
    final requestedUris = <Uri>[];
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        handler: (uri) {
          requestedUris.add(uri);
          if (uri.path.endsWith('/api/releases/latest')) {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'version': '1.1.0',
                'release_page_url':
                    'https://updates.example.com/releases/v1.1.0',
                'platforms': {
                  'linux-x64': {
                    'install_mode': 'bundle-tar-gz',
                    'archive_url':
                        'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
                    'sha256': 'abc123',
                  },
                },
              }),
            );
          }
          if (uri.path.endsWith('/api/releases/latest.sig')) {
            return const _FakeHttpResponse(
              statusCode: 404,
              body: 'missing',
            );
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseApiOriginOverride: 'https://updates.example.com/custom/base',
      releaseRepoOverride: '',
      updatePublicKeyOverride:
          base64Encode(List<int>.generate(32, (i) => i + 1)),
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNull);
    expect(result.errorMessage, contains('signature_fetch_failed_404'));
    final requestedPaths = requestedUris.map((uri) => uri.path).toList();
    expect(requestedPaths, contains('/custom/base/api/releases/latest'));
    expect(
      requestedPaths,
      contains('/custom/base/api/releases/latest.sig'),
    );
  });
}

Future<String> _ed25519PublicKeyBase64FromSeed(List<int> seed) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  return base64Encode(publicKey.bytes);
}

Future<String> _signEd25519Base64({
  required List<int> payload,
  required List<int> seed,
}) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final signature = await Ed25519().sign(payload, keyPair: keyPair);
  return base64Encode(signature.bytes);
}

final class _FakeHttpResponse {
  const _FakeHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({this.handler, this.onGetUrl});

  final _FakeHttpResponse Function(Uri uri)? handler;
  final Future<HttpClientRequest> Function(Uri uri)? onGetUrl;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final getUrl = onGetUrl;
    if (getUrl != null) {
      return getUrl(url);
    }
    final responseHandler = handler;
    if (responseHandler == null) {
      throw StateError('missing_handler:$url');
    }
    final response = responseHandler(url);
    return _FakeHttpClientRequest(
      response: _FakeHttpClientResponse(
        statusCode: response.statusCode,
        body: response.body,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({required this.response});

  final HttpClientResponse response;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({required this.statusCode, required String body})
      : _stream = Stream<List<int>>.fromIterable([utf8.encode(body)]);

  final Stream<List<int>> _stream;

  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(
    String name,
    Object value, {
    bool preserveHeaderCase = false,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

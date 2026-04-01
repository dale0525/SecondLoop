import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';

void main() {
  test(
      'falls back to GitHub API when custom manifest endpoint payload is invalid',
      () async {
    final requestedUris = <Uri>[];
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        handler: (uri) {
          requestedUris.add(uri);
          if (uri.host == 'secondloop.app') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'release_page_url':
                    'https://secondloop.app/releases/invalid-payload',
                'platforms': <String, Object?>{},
              }),
            );
          }
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
          if (uri.host == 'api.github.com' &&
              uri.path == '/repos/dale0525/SecondLoop/releases/latest') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'tag_name': 'v1.1.0',
                'html_url':
                    'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
                'assets': [
                  {
                    'name': 'SecondLoop-linux-x64-v1.1.0.tar.gz',
                    'browser_download_url':
                        'https://cdn.example.com/signed.tar.gz',
                    'sha256': 'abc123',
                  },
                ],
              }),
            );
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseApiOriginOverride: 'https://secondloop.app',
      releaseRepoOverride: 'dale0525/SecondLoop',
      updatePublicKeyOverride: '',
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNotNull);
    expect(result.update!.latestTag, 'v1.1.0');
    expect(
        requestedUris.map((uri) => uri.toString()),
        containsAll(<Matcher>[
          contains('https://secondloop.app/api/releases/latest'),
          contains(
              'https://api.github.com/repos/dale0525/SecondLoop/releases/latest'),
        ]));
  });

  test('verifies signatures for custom manifest endpoint payloads', () async {
    final requestedUris = <Uri>[];
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        handler: (uri) {
          requestedUris.add(uri);
          if (uri.host == 'secondloop.app' &&
              uri.path == '/api/releases/latest') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'version': '1.1.0',
                'release_page_url': 'https://secondloop.app/releases/v1.1.0',
                'platforms': {
                  'linux-x64': {
                    'archive_url':
                        'https://cdn.example.com/SecondLoop-linux-x64-v1.1.0.tar.gz',
                    'sha256': 'abc123',
                  },
                },
              }),
            );
          }
          if (uri.host == 'secondloop.app' &&
              uri.path == '/api/releases/latest.sig') {
            return const _FakeHttpResponse(statusCode: 404, body: 'missing');
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseApiOriginOverride: 'https://secondloop.app',
      releaseRepoOverride: '',
      updatePublicKeyOverride: base64Encode(List<int>.generate(32, (i) => i)),
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
      networkTimeoutOverride: const Duration(milliseconds: 20),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNull);
    expect(result.errorMessage, contains('signature_fetch_failed_404'));
    expect(
      requestedUris.map((uri) => uri.toString()),
      contains('https://secondloop.app/api/releases/latest.sig'),
    );
  });

  test('uses latest.json when public key is configured', () async {
    final requestedUris = <Uri>[];
    final latestJsonBody = jsonEncode({
      'version': '1.1.0',
      'release_page_url':
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      'platforms': {
        'linux-x64': {
          'install_mode': 'bundle-tar-gz',
          'archive_url': 'https://cdn.example.com/from-latest-json.tar.gz',
          'sha256': 'abc123',
        },
      },
    });
    final signingSeed = List<int>.generate(32, (i) => i);
    final signingPublicKey = await _publicKeyBase64FromSeed(signingSeed);
    final latestJsonSignature =
        await _signBodyBase64(latestJsonBody, seed: signingSeed);
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
              body: latestJsonBody,
            );
          }
          if (uri.host == 'api.github.com' &&
              uri.path == '/repos/dale0525/SecondLoop/releases/latest') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'tag_name': 'v1.1.0',
                'html_url':
                    'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
                'assets': [
                  {
                    'name': 'SecondLoop-linux-x64-v1.1.0.tar.gz',
                    'browser_download_url':
                        'https://cdn.example.com/from-github-api.tar.gz',
                    'sha256': 'def456',
                  },
                ],
              }),
            );
          }
          if (uri.path.endsWith('latest.json.sig')) {
            return _FakeHttpResponse(
                statusCode: 200, body: latestJsonSignature);
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseRepoOverride: 'dale0525/SecondLoop',
      updatePublicKeyOverride: signingPublicKey,
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNotNull);
    expect(
      result.update!.downloadUri.toString(),
      'https://cdn.example.com/from-latest-json.tar.gz',
    );
    expect(requestedUris.map((uri) => uri.path),
        contains(endsWith('latest.json')));
    expect(requestedUris.map((uri) => uri.path),
        contains(endsWith('latest.json.sig')));
    expect(messages, isEmpty);
  });

  test(
      'does not fall back to unsigned GitHub API when public key is configured',
      () async {
    final requestedUris = <Uri>[];
    final signingSeed = List<int>.generate(32, (i) => i);
    final signingPublicKey = await _publicKeyBase64FromSeed(signingSeed);
    const invalidManifestBody = '{"version":"1.1.0","platforms":';
    final invalidManifestSignature =
        await _signBodyBase64(invalidManifestBody, seed: signingSeed);

    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        handler: (uri) {
          requestedUris.add(uri);
          if (uri.path.endsWith('latest.json')) {
            return const _FakeHttpResponse(
              statusCode: 200,
              body: invalidManifestBody,
            );
          }
          if (uri.path.endsWith('latest.json.sig')) {
            return _FakeHttpResponse(
              statusCode: 200,
              body: invalidManifestSignature,
            );
          }
          if (uri.host == 'api.github.com' &&
              uri.path == '/repos/dale0525/SecondLoop/releases/latest') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'tag_name': 'v1.1.0',
                'html_url':
                    'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
                'assets': [
                  {
                    'name': 'SecondLoop-linux-x64-v1.1.0.tar.gz',
                    'browser_download_url':
                        'https://cdn.example.com/from-github-api.tar.gz',
                    'sha256': 'def456',
                  },
                ],
              }),
            );
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseRepoOverride: 'dale0525/SecondLoop',
      updatePublicKeyOverride: signingPublicKey,
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNull);
    expect(result.errorMessage, isNotNull);
    expect(
      requestedUris.where((uri) => uri.host == 'api.github.com'),
      isEmpty,
    );
  });

  test(
      'falls through to later endpoint when earlier payload lacks current platform asset',
      () async {
    final requestedUris = <Uri>[];
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        handler: (uri) {
          requestedUris.add(uri);
          if (uri.host == 'secondloop.app' &&
              uri.path == '/api/releases/latest') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'version': '1.1.0',
                'release_page_url': 'https://secondloop.app/releases/v1.1.0',
                'platforms': {
                  'android-universal': {
                    'archive_url':
                        'https://cdn.example.com/SecondLoop-android-v1.1.0.apk',
                    'sha256': 'android-only',
                  },
                },
              }),
            );
          }
          if (uri.host == 'api.github.com' &&
              uri.path == '/repos/dale0525/SecondLoop/releases/latest') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'tag_name': 'v1.1.0',
                'html_url':
                    'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
                'assets': [
                  {
                    'name': 'SecondLoop-linux-x64-v1.1.0.tar.gz',
                    'browser_download_url':
                        'https://cdn.example.com/from-github-api.tar.gz',
                    'sha256': 'linux',
                  },
                ],
              }),
            );
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseApiOriginOverride: 'https://secondloop.app',
      releaseRepoOverride: 'dale0525/SecondLoop',
      updatePublicKeyOverride: '',
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNotNull);
    expect(
      result.update!.downloadUri.toString(),
      'https://cdn.example.com/from-github-api.tar.gz',
    );
    expect(
      requestedUris.map((uri) => uri.toString()),
      containsAll(<String>[
        'https://secondloop.app/api/releases/latest',
        'https://api.github.com/repos/dale0525/SecondLoop/releases/latest',
      ]),
    );
  });

  test('returns no update when all endpoints lack current platform assets',
      () async {
    final requestedUris = <Uri>[];
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        handler: (uri) {
          requestedUris.add(uri);
          if (uri.host == 'secondloop.app' &&
              uri.path == '/api/releases/latest') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'version': '1.1.0',
                'release_page_url': 'https://secondloop.app/releases/v1.1.0',
                'platforms': {
                  'android-universal': {
                    'archive_url':
                        'https://cdn.example.com/SecondLoop-android-v1.1.0.apk',
                    'sha256': 'android-only',
                  },
                },
              }),
            );
          }
          if (uri.host == 'api.github.com' &&
              uri.path == '/repos/dale0525/SecondLoop/releases/latest') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'tag_name': 'v1.1.0',
                'html_url':
                    'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
                'assets': [
                  {
                    'name': 'SecondLoop-android-arm64-v8a-v1.1.0.apk',
                    'browser_download_url':
                        'https://cdn.example.com/from-github-api.apk',
                    'sha256': 'android',
                  },
                ],
              }),
            );
          }
          throw StateError('unexpected_uri:$uri');
        },
      ),
      platformOverride: AppUpdatePlatform.linux,
      releaseModeOverride: true,
      releaseApiOriginOverride: 'https://secondloop.app',
      releaseRepoOverride: 'dale0525/SecondLoop',
      updatePublicKeyOverride: '',
      currentVersionLoader: () async =>
          const AppRuntimeVersion(version: '1.0.0', buildNumber: '1'),
    );

    final result = await service.checkForUpdates();

    expect(result.update, isNull);
    expect(result.errorMessage, contains('no_platform_asset_for_linux'));
    expect(
      requestedUris.map((uri) => uri.toString()),
      containsAll(<String>[
        'https://secondloop.app/api/releases/latest',
        'https://api.github.com/repos/dale0525/SecondLoop/releases/latest',
      ]),
    );
  });

  test('prefers GitHub API over unsigned latest.json when public key is unset',
      () async {
    final requestedUris = <Uri>[];
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        handler: (uri) {
          requestedUris.add(uri);
          if (uri.path.endsWith('latest.json')) {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'version': '9.9.9',
                'release_page_url':
                    'https://github.com/dale0525/SecondLoop/releases/tag/v9.9.9',
                'platforms': {
                  'linux-x64': {
                    'install_mode': 'bundle-tar-gz',
                    'archive_url': 'https://cdn.example.com/unsigned.tar.gz',
                    'sha256': 'unsigned',
                  },
                },
              }),
            );
          }
          if (uri.host == 'api.github.com' &&
              uri.path == '/repos/dale0525/SecondLoop/releases/latest') {
            return _FakeHttpResponse(
              statusCode: 200,
              body: jsonEncode({
                'tag_name': 'v1.1.0',
                'html_url':
                    'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
                'assets': [
                  {
                    'name': 'SecondLoop-linux-x64-v1.1.0.tar.gz',
                    'browser_download_url':
                        'https://cdn.example.com/signed.tar.gz',
                    'sha256': 'abc123',
                  },
                ],
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
    expect(result.update!.latestTag, 'v1.1.0');
    expect(result.update!.downloadUri.toString(),
        'https://cdn.example.com/signed.tar.gz');
    expect(
      requestedUris.map((uri) => uri.toString()),
      contains(
          'https://api.github.com/repos/dale0525/SecondLoop/releases/latest'),
    );
    expect(
      requestedUris.map((uri) => uri.toString()),
      isNot(contains(
          'https://github.com/dale0525/SecondLoop/releases/latest/download/latest.json')),
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

Future<String> _signBodyBase64(
  String body, {
  required List<int> seed,
}) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final signature = await algorithm.sign(utf8.encode(body), keyPair: keyPair);
  return base64Encode(signature.bytes);
}

Future<String> _publicKeyBase64FromSeed(List<int> seed) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  return base64Encode(publicKey.bytes);
}

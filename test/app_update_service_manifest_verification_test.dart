import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
}

final class _FakeHttpResponse {
  const _FakeHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({required this.handler});

  final _FakeHttpResponse Function(Uri uri) handler;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final response = handler(url);
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

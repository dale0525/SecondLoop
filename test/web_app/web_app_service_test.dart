import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:secondloop/web_app/web_app_service.dart';

void main() {
  test('loadConfig parses managed vault availability from runtime config',
      () async {
    final client = _FakeHttpClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/cloud/config');
      return http.Response(
        jsonEncode(<String, Object?>{
          'ok': true,
          'firebase_web_api_key': 'firebase-key',
          'has_managed_vault_base_url': false,
        }),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    final config = await WebAppServiceHttp.loadConfig(client: client);

    expect(config.firebaseWebApiKey, 'firebase-key');
    expect(config.hasManagedVaultBaseUrl, isFalse);
  });

  test('fetchVaultUsage skips HTTP when managed vault is unavailable',
      () async {
    final client = _FakeHttpClient((request) async {
      fail(
          'fetchVaultUsage should not hit HTTP when managed vault is unavailable');
    });
    final service = WebAppServiceHttp(
      client: client,
      managedVaultConfigured: false,
    );

    final summary = await service.fetchVaultUsage(
      idToken: 'token',
      vaultId: 'vault-1',
    );

    expect(summary, isNull);
    expect(client.requestCount, 0);
  });

  test('listVaultAttachments skips HTTP when managed vault is unavailable',
      () async {
    final client = _FakeHttpClient((request) async {
      fail(
        'listVaultAttachments should not hit HTTP when managed vault is unavailable',
      );
    });
    final service = WebAppServiceHttp(
      client: client,
      managedVaultConfigured: false,
    );

    final items = await service.listVaultAttachments(
      idToken: 'token',
      vaultId: 'vault-1',
    );

    expect(items, isEmpty);
    expect(client.requestCount, 0);
  });
}

final class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount += 1;
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

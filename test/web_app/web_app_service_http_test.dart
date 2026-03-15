import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/web_app/web_app_gate.dart';

void main() {
  test('vault requests include x-secondloop-vault-id header', () async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/usage')) {
        return http.Response(jsonEncode({'total_bytes_used': 1}), 200);
      }
      return http.Response(jsonEncode({'items': []}), 200);
    });

    final service = WebAppServiceHttp(client: client);

    await service.fetchVaultUsage(idToken: 'token', vaultId: 'vault-123');
    await service.listVaultAttachments(idToken: 'token', vaultId: 'vault-123');

    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(request.headers['authorization'], 'Bearer token');
      expect(request.headers['x-secondloop-vault-id'], 'vault-123');
    }
  });

  test('vault attachment bytes request includes auth and vault headers',
      () async {
    http.BaseRequest? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes('hello world'.codeUnits, 200, headers: {
        'content-type': 'text/plain',
      });
    });

    final service = WebAppServiceHttp(client: client);
    final bytes = await service.fetchVaultAttachmentBytes(
      idToken: 'token',
      vaultId: 'vault-123',
      sha256: 'sha-1',
    );

    expect(String.fromCharCodes(bytes), 'hello world');
    expect(captured, isNotNull);
    expect(captured!.headers['authorization'], 'Bearer token');
    expect(captured!.headers['x-secondloop-vault-id'], 'vault-123');
  });
}

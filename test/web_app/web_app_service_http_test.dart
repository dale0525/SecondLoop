import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
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

  test('grouped vault attachments preserve root and group metadata', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'items': [
            {
              'sha256': 'leaf-sha',
              'root_sha256': 'root-sha',
              'group_type': 'video',
              'leaf_count': 3,
              'mime_type': 'video/mp4',
              'byte_len': 4096,
              'created_at_ms': 1000,
              'uploaded_at_ms': 2000,
            },
          ],
        }),
        200,
      );
    });

    final service = WebAppServiceHttp(client: client);
    final items = await service.listVaultAttachments(
      idToken: 'token',
      vaultId: 'vault-123',
    );

    expect(items, hasLength(1));
    expect(items.single.sha256, 'leaf-sha');
    expect(items.single.rootSha256, 'root-sha');
    expect(items.single.groupType, 'video');
    expect(items.single.leafCount, 3);
    expect(items.single.primarySha256, 'root-sha');
  });

  test('usage errors preserve parseable http status and cloud code', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'error': 'rate_limited'}),
        429,
      );
    });

    final service = WebAppServiceHttp(client: client);

    await expectLater(
      () => service.fetchUsage(idToken: 'token'),
      throwsA(
        isA<Object>()
            .having(parseHttpStatusFromError, 'status', 429)
            .having(parseCloudErrorCodeFromError, 'cloudCode', 'rate_limited'),
      ),
    );
  });

  test('vault upload sends put request to attachment route with sha query',
      () async {
    http.BaseRequest? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{}', 200);
    });

    final service = WebAppServiceHttp(client: client);
    await service.uploadVaultAttachment(
      idToken: 'token',
      vaultId: 'vault-123',
      fileName: 'note.txt',
      mimeType: 'text/plain',
      bytes: 'hello'.codeUnits,
    );

    expect(captured, isNotNull);
    expect(captured!.method, 'PUT');
    expect(captured!.url.path, '/api/app/vault/attachment');
    expect(
      captured!.url.queryParameters['sha256'],
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    );
    expect(captured!.headers['authorization'], 'Bearer token');
    expect(captured!.headers['x-secondloop-vault-id'], 'vault-123');
  });
}

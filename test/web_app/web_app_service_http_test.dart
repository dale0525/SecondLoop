import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/web_app/web_app_gate.dart';

void main() {
  test('loadConfig parses managed vault base URL from runtime config',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/cloud/config');
      return http.Response(
        jsonEncode({
          'ok': true,
          'firebase_web_api_key': 'firebase-key',
          'has_managed_vault_base_url': true,
          'managed_vault_base_url': 'https://vault.secondloop.example',
        }),
        200,
      );
    });

    final config = await WebAppServiceHttp.loadConfig(client: client);

    expect(config.firebaseWebApiKey, 'firebase-key');
    expect(config.hasManagedVaultBaseUrl, isTrue);
    expect(config.managedVaultBaseUrl, 'https://vault.secondloop.example');
  });

  test('chat request sends messages only and does not expose model overrides',
      () async {
    http.BaseRequest? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'content': 'ok'}), 200);
    });

    final service = WebAppServiceHttp(client: client);
    await service.sendChat(
      idToken: 'token',
      messages: const <Map<String, String>>[
        <String, String>{'role': 'user', 'content': 'hello'},
      ],
    );

    expect(captured, isNotNull);
    final request = captured! as http.Request;
    final decoded = jsonDecode(request.body) as Map<String, dynamic>;
    expect(decoded['model_name'], isNull);
    expect(decoded['gateway_base_url'], isNull);
    expect(decoded['messages'], isNotNull);
  });

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

  test('managed-vault v2 pull page uses proxy path and parses response',
      () async {
    http.BaseRequest? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'generation_id': 'generation-1',
          'remote_latest_global_seq': 2,
          'has_more': false,
          'ops': [
            {
              'global_seq': 1,
              'device_id': 'device-a',
              'seq': 13,
              'op_id': 'op-1',
              'client_op_id': 'op-1',
              'ciphertext_b64': 'AQID',
            },
            {
              'global_seq': 2,
              'device_id': 'device-a',
              'seq': 14,
              'op_id': 'op-2',
              'client_op_id': 'op-2',
              'ciphertext_b64': 'BAUG',
            },
          ],
        }),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    final service = WebAppServiceHttp(client: client);
    final page = await service.fetchManagedVaultPullPage(
      idToken: 'token',
      vaultId: 'vault-123',
      afterGlobalSeq: 0,
    );

    expect(captured, isNotNull);
    final request = captured! as http.Request;
    expect(request.method, 'POST');
    expect(
      request.url.path,
      '/api/app/vault-proxy/v2/vaults/vault-123/sync/pull',
    );
    expect(request.headers['authorization'], 'Bearer token');
    expect(request.headers['x-secondloop-vault-id'], 'vault-123');
    expect(
      jsonDecode(request.body),
      <String, Object?>{
        'after_global_seq': 0,
        'limit': 500,
      },
    );
    expect(page.generationId, 'generation-1');
    expect(page.remoteLatestGlobalSeq, 2);
    expect(page.hasMore, isFalse);
    expect(page.ops, hasLength(2));
    expect(page.ops.first.globalSeq, 1);
    expect(page.ops.last.opId, 'op-2');
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

  test('vault attachment bytes reject oversized browser downloads early',
      () async {
    http.BaseRequest? captured;
    final client = _FakeStreamedClient((request) async {
      captured = request;
      return http.StreamedResponse(
        Stream<List<int>>.value('ok'.codeUnits),
        200,
        contentLength: 50 * 1024 * 1024 + 1,
        headers: const <String, String>{
          'content-type': 'application/octet-stream',
        },
      );
    });

    final service = WebAppServiceHttp(client: client);

    await expectLater(
      () => service.fetchVaultAttachmentBytes(
        idToken: 'token',
        vaultId: 'vault-123',
        sha256: 'sha-oversized',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'attachment_too_large_for_web',
        ),
      ),
    );
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

  test('non-json errors preserve parseable http status and raw body', () async {
    final client = MockClient((request) async {
      return http.Response(
        '<html><body>gateway down</body></html>',
        502,
        headers: const <String, String>{
          'content-type': 'text/html',
        },
      );
    });

    final service = WebAppServiceHttp(client: client);

    await expectLater(
      () => service.fetchUsage(idToken: 'token'),
      throwsA(
        isA<Object>().having(parseHttpStatusFromError, 'status', 502).having(
              (error) => error.toString(),
              'body',
              contains('gateway down'),
            ),
      ),
    );
  });

  test('checkout throws when browser cannot open the billing url', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(
            {'checkout_url': 'https://checkout.secondloop.test/session'}),
        200,
      );
    });

    final service = WebAppServiceHttp(
      client: client,
      urlOpener: (_) async => false,
    );

    await expectLater(
      () => service.openCheckout(idToken: 'token'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'open_url_failed',
        ),
      ),
    );
  });

  test('vault upload rejects oversized browser payloads before sending',
      () async {
    var sendCalled = false;
    final client = _FakeStreamedClient((request) async {
      sendCalled = true;
      return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
    });

    final service = WebAppServiceHttp(client: client);

    await expectLater(
      () => service.uploadVaultAttachment(
        idToken: 'token',
        vaultId: 'vault-123',
        fileName: 'big.bin',
        mimeType: 'application/octet-stream',
        bytes: List<int>.filled(50 * 1024 * 1024 + 1, 7),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'attachment_too_large_for_web',
        ),
      ),
    );
    expect(sendCalled, isFalse);
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
      fileName: '中文🙂.txt',
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
    expect(
      captured!.headers['x-file-name'],
      Uri.encodeComponent('中文🙂.txt'),
    );
  });

  test('guessMimeTypeFromExtension maps docx and webm to stable types', () {
    expect(
      guessMimeTypeFromExtension('docx'),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    expect(
      guessMimeTypeFromExtension('WEBM'),
      'video/webm',
    );
  });
}

final class _FakeStreamedClient extends http.BaseClient {
  _FakeStreamedClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

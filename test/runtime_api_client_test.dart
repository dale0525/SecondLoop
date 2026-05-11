import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/runtime_api_client.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('client resolves paths against the active manifest base url', () async {
    final store = RuntimeConnectionStore();
    await store.saveConnection(
      const CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: 'https://user-runtime.example/root/',
          authMode: CloudRuntimeAuthMode.runtimeToken,
          authToken: 'runtime-token-1',
          capabilityManifestId: 'manifest-self-1',
          manifestVersion: 1,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: 1,
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: 'https://user-runtime.example/root/',
          authMode: CloudRuntimeAuthMode.runtimeToken,
          capabilities: [CloudRuntimeCapability('chat')],
        ),
      ),
    );

    late Uri requestedUri;
    final client = RuntimeApiClient(
      connectionStore: store,
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await client.getJson('/v1/runtime/capabilities');

    expect(
      requestedUri.toString(),
      'https://user-runtime.example/v1/runtime/capabilities',
    );
  });

  test('client injects auth headers from the active runtime profile', () async {
    final store = RuntimeConnectionStore();
    await store.saveConnection(
      const CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: 'https://user-runtime.example/',
          authMode: CloudRuntimeAuthMode.runtimeToken,
          authToken: 'runtime-token-1',
          capabilityManifestId: 'manifest-self-1',
          manifestVersion: 1,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: 1,
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: 'https://user-runtime.example/',
          authMode: CloudRuntimeAuthMode.runtimeToken,
          capabilities: [CloudRuntimeCapability('chat')],
        ),
      ),
    );

    late http.BaseRequest capturedRequest;
    final client = RuntimeApiClient(
      connectionStore: store,
      httpClient: MockClient((request) async {
        capturedRequest = request;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await client.getJson('/v1/runtime/capabilities');

    expect(
      capturedRequest.headers['authorization'],
      'Bearer runtime-token-1',
    );
  });

  test('hosted managed pro runtime uses gateway bearer authorization',
      () async {
    final store = RuntimeConnectionStore();
    await store.saveConnection(
      const CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: 'https://gateway.example/',
          authMode: CloudRuntimeAuthMode.hostedSession,
          authToken: 'hosted-id-token-1',
          capabilityManifestId: 'manifest-managed-1',
          manifestVersion: 1,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: 1,
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: 'https://gateway.example/',
          authMode: CloudRuntimeAuthMode.hostedSession,
          capabilities: [CloudRuntimeCapability('chat')],
        ),
      ),
    );

    late http.BaseRequest capturedRequest;
    final client = RuntimeApiClient(
      connectionStore: store,
      httpClient: MockClient((request) async {
        capturedRequest = request;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await client.postJson(
      '/v1/runtime/vaults/managed-user-1/conversations/loop_home/messages',
      body: const <String, Object?>{'message': '帮我创建一个任务：完成周报。'},
    );

    expect(
      capturedRequest.headers['authorization'],
      'Bearer hosted-id-token-1',
    );
    expect(
      capturedRequest.headers.containsKey('x-secondloop-hosted-session'),
      isFalse,
    );
  });

  test('client decodes runtime JSON as UTF-8 when charset is omitted',
      () async {
    final store = RuntimeConnectionStore();
    await store.saveConnection(
      const CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: 'https://gateway.example/',
          authMode: CloudRuntimeAuthMode.hostedSession,
          authToken: 'hosted-id-token-1',
          capabilityManifestId: 'manifest-managed-1',
          manifestVersion: 1,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: 1,
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: 'https://gateway.example/',
          authMode: CloudRuntimeAuthMode.hostedSession,
          capabilities: [CloudRuntimeCapability('chat')],
        ),
      ),
    );

    final client = RuntimeApiClient(
      connectionStore: store,
      httpClient: MockClient((_) async {
        return http.Response.bytes(
          utf8.encode('{"assistant":{"content":"已创建任务：完成周报。"}}'),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.getJson('/v1/runtime/runs/run-1');

    expect(
      (response?['assistant'] as Map<String, dynamic>)['content'],
      '已创建任务：完成周报。',
    );
  });

  test('non-2xx responses return structured runtime exceptions', () async {
    final store = RuntimeConnectionStore();
    await store.saveConnection(
      const CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: 'https://hosted-runtime.example/',
          authMode: CloudRuntimeAuthMode.hostedSession,
          authToken: 'hosted-session-1',
          capabilityManifestId: 'manifest-managed-1',
          manifestVersion: 1,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: 1,
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: 'https://hosted-runtime.example/',
          authMode: CloudRuntimeAuthMode.hostedSession,
          capabilities: [CloudRuntimeCapability('chat')],
        ),
      ),
    );

    final client = RuntimeApiClient(
      connectionStore: store,
      httpClient: MockClient(
        (_) async => http.Response('{"error":"denied"}', 403),
      ),
    );

    await expectLater(
      () => client.getJson('/v1/runtime/capabilities'),
      throwsA(
        isA<CloudRuntimeApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.responseBody, 'responseBody',
                contains('denied')),
      ),
    );
  });

  test('api exceptions include response details in toString', () {
    final error = CloudRuntimeApiException(
      uri: Uri(scheme: 'https', host: 'runtime.example', path: '/v1/test'),
      statusCode: 400,
      responseBody: '{"error":"missing_task_mutation_target"}',
    );

    expect(error.toString(), contains('400'));
    expect(error.toString(), contains('/v1/test'));
    expect(error.toString(), contains('missing_task_mutation_target'));
  });
}

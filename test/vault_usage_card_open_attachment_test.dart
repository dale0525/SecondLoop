import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/settings/vault_usage_card.dart';

import 'test_i18n.dart';

Future<void> _pumpUi(WidgetTester tester, {int cycles = 16}) async {
  for (var i = 0; i < cycles; i += 1) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 24,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 32));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets(
      'VaultUsageCard opens grouped video attachment preview by root sha',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const rootSha = 'sha-video-root';
    const leafSha = 'sha-video-segment';
    final launchedUrls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launchedUrls.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final httpClient = _MultiResponseHttpClient(
      handlers: <Pattern, _FakeHttpResponse>{
        RegExp(r'/v1/vaults/uid_1/usage$'): _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'total_bytes_used': 4096,
            'attachments_bytes_used': 4096,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': null,
          }),
        ),
        RegExp(r'/v1/vaults/uid_1/attachments$'): _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'items': [
              {
                'sha256': leafSha,
                'root_sha256': rootSha,
                'group_type': 'video',
                'leaf_count': 4,
                'mime_type': 'video',
                'byte_len': 4096,
                'created_at_ms': 1000,
                'uploaded_at_ms': 2000,
              },
            ],
            'total_count': 1,
            'total_bytes_used': 4096,
          }),
        ),
        RegExp(r'/v1/vaults/uid_1/attachments/sha-video-root/preview$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'kind': 'video',
            'url': 'https://signed.test/video-preview',
            'thumbnail_url': 'https://signed.test/video-thumb',
          }),
        ),
      },
    );

    await tester.pumpWidget(
      wrapWithI18n(
        CloudAuthScope(
          controller: _FakeCloudAuthController(),
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'cloud',
          ),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              home: Scaffold(
                body: VaultUsageCard(
                  client: VaultUsageClient(httpClient: httpClient),
                  attachmentsClient:
                      VaultAttachmentsClient(httpClient: httpClient),
                  configStore: SyncConfigStore(
                    managedVaultDefaultBaseUrl: 'https://vault.test',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await _pumpUi(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('vault_usage_refresh')));
    await _pumpUi(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault_usage_attachment_$rootSha')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('vault_usage_attachment_$rootSha')));
    await tester.pump();
    await _pumpUi(tester);

    expect(
      httpClient.getUrls,
      contains('https://vault.test/v1/vaults/uid_1/attachments/$rootSha'
          '/preview'),
    );
    expect(launchedUrls, ['https://signed.test/video-preview']);
  });

  testWidgets(
      'VaultUsageCard deduplicates same-auth refreshes during initial load',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault-1.test',
    );
    final requestCounts = <String, int>{};
    final httpClient = MockClient((request) async {
      final url = request.url.toString();
      requestCounts[url] = (requestCounts[url] ?? 0) + 1;
      if (url == 'https://vault-1.test/v1/vaults/uid_1/usage') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'total_bytes_used': 1024,
            'attachments_bytes_used': 1024,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': null,
          }),
          200,
        );
      }
      if (url == 'https://vault-1.test/v1/vaults/uid_1/attachments?limit=200') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'items': const <Object?>[],
            'total_count': 0,
            'total_bytes_used': 0,
          }),
          200,
        );
      }
      throw StateError('unexpected url: $url');
    });

    await tester.pumpWidget(
      wrapWithI18n(
        CloudAuthScope(
          controller: _FakeCloudAuthController(),
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'cloud',
          ),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              home: Scaffold(
                body: VaultUsageCard(
                  client: VaultUsageClient(httpClient: httpClient),
                  attachmentsClient:
                      VaultAttachmentsClient(httpClient: httpClient),
                  configStore: store,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUi(tester);
    await tester.pumpAndSettle();

    expect(requestCounts['https://vault-1.test/v1/vaults/uid_1/usage'], 1);
    expect(
      requestCounts[
          'https://vault-1.test/v1/vaults/uid_1/attachments?limit=200'],
      1,
    );
  });

  testWidgets('VaultUsageCard repairs zero summary from attachment inventory',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final httpClient = MockClient((request) async {
      final url = request.url.toString();
      if (url == 'https://vault-1.test/v1/vaults/uid_1/usage') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'total_bytes_used': 0,
            'attachments_bytes_used': 0,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': null,
          }),
          200,
        );
      }
      if (url == 'https://vault-1.test/v1/vaults/uid_1/attachments?limit=200') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'items': [
              {
                'id': 'att-a',
                'sha256': 'sha-a',
                'display_name': 'scan-a.pdf',
                'mime_type': 'application/pdf',
                'byte_len': 7,
                'created_at_ms': 1000,
                'uploaded_at_ms': 2000,
              },
              {
                'id': 'att-b',
                'sha256': 'sha-b',
                'display_name': 'scan-b.pdf',
                'mime_type': 'application/pdf',
                'byte_len': 5,
                'created_at_ms': 3000,
                'uploaded_at_ms': 4000,
              },
            ],
            'total_count': 2,
            'total_bytes_used': 12,
          }),
          200,
        );
      }
      throw StateError('unexpected url: $url');
    });

    await tester.pumpWidget(
      wrapWithI18n(
        CloudAuthScope(
          controller: _FakeCloudAuthController(),
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'cloud',
          ),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              home: Scaffold(
                body: VaultUsageCard(
                  client: VaultUsageClient(httpClient: httpClient),
                  attachmentsClient:
                      VaultAttachmentsClient(httpClient: httpClient),
                  configStore: SyncConfigStore(
                    managedVaultDefaultBaseUrl: 'https://vault-1.test',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUi(tester);
    await tester.pumpAndSettle();

    expect(find.text('12 B'), findsNWidgets(2));
    expect(find.text('scan-a.pdf'), findsOneWidget);
    expect(find.text('scan-b.pdf'), findsOneWidget);
  });

  testWidgets('VaultUsageCard refreshes when managed vault base URL changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault-1.test',
    );
    final httpClient = _MultiResponseHttpClient(
      handlers: <Pattern, _FakeHttpResponse>{
        RegExp(r'https://vault-1\.test/v1/vaults/uid_1/usage$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'total_bytes_used': 1024,
            'attachments_bytes_used': 1024,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': null,
          }),
        ),
        RegExp(r'https://vault-1\.test/v1/vaults/uid_1/attachments\?limit=200$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'items': [
              {
                'sha256': 'sha-vault-1',
                'mime_type': 'text/plain',
                'byte_len': 10,
                'created_at_ms': 1000,
                'uploaded_at_ms': 2000,
              },
            ],
            'total_count': 1,
            'total_bytes_used': 10,
          }),
        ),
        RegExp(r'https://vault-2\.test/v1/vaults/uid_1/usage$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'total_bytes_used': 2048,
            'attachments_bytes_used': 2048,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': null,
          }),
        ),
        RegExp(r'https://vault-2\.test/v1/vaults/uid_1/attachments\?limit=200$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'items': [
              {
                'sha256': 'sha-vault-2',
                'mime_type': 'text/plain',
                'byte_len': 20,
                'created_at_ms': 3000,
                'uploaded_at_ms': 4000,
              },
            ],
            'total_count': 1,
            'total_bytes_used': 20,
          }),
        ),
      },
    );

    Widget buildWidget() {
      return wrapWithI18n(
        CloudAuthScope(
          controller: _FakeCloudAuthController(),
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'cloud',
          ),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              home: Scaffold(
                body: VaultUsageCard(
                  client: VaultUsageClient(httpClient: httpClient),
                  attachmentsClient:
                      VaultAttachmentsClient(httpClient: httpClient),
                  configStore: store,
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWidget());
    await _pumpUi(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-vault-1')),
        findsOneWidget);

    await store.writeManagedVaultBaseUrl('https://vault-2.test');
    await tester.pumpWidget(buildWidget());
    await _pumpUi(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-vault-2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-vault-1')),
        findsNothing);
  });

  testWidgets('VaultUsageCard uses latest injected config store on rebuild',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store1 = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault-1.test',
    );
    final store2 = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault-2.test',
    );
    final httpClient = _MultiResponseHttpClient(
      handlers: <Pattern, _FakeHttpResponse>{
        RegExp(r'https://vault-1\.test/v1/vaults/uid_1/usage$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'total_bytes_used': 1024,
            'attachments_bytes_used': 1024,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': null,
          }),
        ),
        RegExp(r'https://vault-1\.test/v1/vaults/uid_1/attachments\?limit=200$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'items': [
              {
                'sha256': 'sha-store-1',
                'mime_type': 'text/plain',
                'byte_len': 10,
                'created_at_ms': 1000,
                'uploaded_at_ms': 2000,
              },
            ],
            'total_count': 1,
            'total_bytes_used': 10,
          }),
        ),
        RegExp(r'https://vault-2\.test/v1/vaults/uid_1/usage$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'total_bytes_used': 2048,
            'attachments_bytes_used': 2048,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': null,
          }),
        ),
        RegExp(r'https://vault-2\.test/v1/vaults/uid_1/attachments\?limit=200$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'items': [
              {
                'sha256': 'sha-store-2',
                'mime_type': 'text/plain',
                'byte_len': 20,
                'created_at_ms': 3000,
                'uploaded_at_ms': 4000,
              },
            ],
            'total_count': 1,
            'total_bytes_used': 20,
          }),
        ),
      },
    );

    Widget buildWidget(SyncConfigStore store) {
      return wrapWithI18n(
        CloudAuthScope(
          controller: _FakeCloudAuthController(),
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'cloud',
          ),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              home: Scaffold(
                body: VaultUsageCard(
                  client: VaultUsageClient(httpClient: httpClient),
                  attachmentsClient:
                      VaultAttachmentsClient(httpClient: httpClient),
                  configStore: store,
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWidget(store1));
    await _pumpUi(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vault_usage_refresh')));
    await _pumpUi(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-store-1')),
        findsOneWidget);

    await tester.pumpWidget(buildWidget(store2));
    await _pumpUi(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vault_usage_refresh')));
    await _pumpUi(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-store-2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-store-1')),
        findsNothing);
  });

  testWidgets(
      'VaultUsageCard ignores stale refresh results after managed vault url changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault-1.test',
    );
    final firstAttachments = Completer<http.Response>();
    final secondUsage = Completer<http.Response>();
    final secondAttachments = Completer<http.Response>();
    final requestedUrls = <String>[];

    final httpClient = MockClient((request) {
      final url = request.url.toString();
      requestedUrls.add(url);
      if (url == 'https://vault-1.test/v1/vaults/uid_1/usage') {
        return Future<http.Response>.value(
          http.Response(
            jsonEncode(<String, Object?>{
              'total_bytes_used': 1024,
              'attachments_bytes_used': 1024,
              'ops_bytes_used': 0,
              'other_bytes_used': 0,
              'limit_bytes': null,
            }),
            200,
          ),
        );
      }
      if (url == 'https://vault-1.test/v1/vaults/uid_1/attachments?limit=200') {
        return firstAttachments.future;
      }
      if (url == 'https://vault-2.test/v1/vaults/uid_1/usage') {
        return secondUsage.future;
      }
      if (url == 'https://vault-2.test/v1/vaults/uid_1/attachments?limit=200') {
        return secondAttachments.future;
      }
      throw StateError('unexpected url: $url');
    });

    Widget buildWidget() {
      return wrapWithI18n(
        CloudAuthScope(
          controller: _FakeCloudAuthController(),
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'cloud',
          ),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              home: Scaffold(
                body: VaultUsageCard(
                  client: VaultUsageClient(httpClient: httpClient),
                  attachmentsClient:
                      VaultAttachmentsClient(httpClient: httpClient),
                  configStore: store,
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(
      requestedUrls,
      contains('https://vault-1.test/v1/vaults/uid_1/attachments?limit=200'),
    );

    await store.writeManagedVaultBaseUrl('https://vault-2.test');
    await tester.pumpWidget(buildWidget());
    await _pumpUi(tester, cycles: 4);

    expect(
      requestedUrls,
      contains('https://vault-2.test/v1/vaults/uid_1/usage'),
    );

    secondUsage.complete(
      http.Response(
        jsonEncode(<String, Object?>{
          'total_bytes_used': 2048,
          'attachments_bytes_used': 2048,
          'ops_bytes_used': 0,
          'other_bytes_used': 0,
          'limit_bytes': null,
        }),
        200,
      ),
    );
    secondAttachments.complete(
      http.Response(
        jsonEncode(<String, Object?>{
          'items': [
            {
              'sha256': 'sha-race-2',
              'mime_type': 'text/plain',
              'byte_len': 20,
              'created_at_ms': 3000,
              'uploaded_at_ms': 4000,
            },
          ],
          'total_count': 1,
          'total_bytes_used': 20,
        }),
        200,
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('vault_usage_attachment_sha-race-2')),
    );

    firstAttachments.complete(
      http.Response(
        jsonEncode(<String, Object?>{
          'items': [
            {
              'sha256': 'sha-race-1',
              'mime_type': 'text/plain',
              'byte_len': 10,
              'created_at_ms': 1000,
              'uploaded_at_ms': 2000,
            },
          ],
          'total_count': 1,
          'total_bytes_used': 10,
        }),
        200,
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('vault_usage_attachment_sha-race-2')),
    );
    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-race-1')),
        findsNothing);
  });

  testWidgets('VaultUsageCard deletes grouped video attachment by root sha',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const rootSha = 'sha-video-root';
    const leafSha = 'sha-video-segment';

    final httpClient = _MultiResponseHttpClient(
      handlers: <Pattern, _FakeHttpResponse>{
        RegExp(r'/v1/vaults/uid_1/usage$'): _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'total_bytes_used': 4096,
            'attachments_bytes_used': 4096,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': null,
          }),
        ),
        RegExp(r'/v1/vaults/uid_1/attachments$'): _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'items': [
              {
                'sha256': leafSha,
                'root_sha256': rootSha,
                'group_type': 'video',
                'leaf_count': 4,
                'mime_type': 'video',
                'byte_len': 4096,
                'created_at_ms': 1000,
                'uploaded_at_ms': 2000,
              },
            ],
            'total_count': 1,
            'total_bytes_used': 4096,
          }),
        ),
        RegExp(r'/v1/vaults/uid_1/attachments/sha-video-root/delete-impact$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'requires_confirmation': true,
            'linked_entities': [
              {
                'kind': 'note',
                'id': 'note-1',
                'title': 'Loop',
              },
            ],
          }),
        ),
        RegExp(r'/v1/vaults/uid_1/attachments/sha-video-root$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'deleted': true,
            'sha256': rootSha,
          }),
        ),
      },
    );

    await tester.pumpWidget(
      wrapWithI18n(
        CloudAuthScope(
          controller: _FakeCloudAuthController(),
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'cloud',
          ),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              home: Scaffold(
                body: VaultUsageCard(
                  client: VaultUsageClient(httpClient: httpClient),
                  attachmentsClient:
                      VaultAttachmentsClient(httpClient: httpClient),
                  configStore: SyncConfigStore(
                    managedVaultDefaultBaseUrl: 'https://vault.test',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await _pumpUi(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('vault_usage_refresh')));
    await _pumpUi(tester);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('vault_usage_attachment_delete_$rootSha'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('vault_usage_attachment_delete_confirm_$rootSha'),
      ),
    );
    await _pumpUi(tester);

    expect(httpClient.deletePaths, ['/v1/vaults/uid_1/attachments/$rootSha']);
    expect(
      httpClient.getUrls,
      contains('https://vault.test/v1/vaults/uid_1/attachments/$rootSha'
          '/delete-impact'),
    );
  });
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => 'test@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'token_1';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

final class _FakeHttpResponse {
  _FakeHttpResponse({required this.statusCode, required this.body});

  factory _FakeHttpResponse.ok(String body) =>
      _FakeHttpResponse(statusCode: 200, body: body);

  final int statusCode;
  final String body;
}

final class _MultiResponseHttpClient extends http.BaseClient {
  _MultiResponseHttpClient({required this.handlers});

  final Map<Pattern, _FakeHttpResponse> handlers;
  final List<String> deletePaths = <String>[];
  final List<String> getUrls = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    switch (request.method) {
      case 'GET':
        getUrls.add(url.toString());
      case 'DELETE':
        deletePaths.add(url.path);
    }

    final response = _resolve(url) ??
        _FakeHttpResponse(statusCode: 404, body: 'no handler for $url');
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(response.body)]),
      response.statusCode,
      request: request,
      headers: const <String, String>{
        'content-type': 'application/json',
      },
    );
  }

  _FakeHttpResponse? _resolve(Uri url) {
    final fullUrl = url.toString();
    final path = url.path;
    for (final entry in handlers.entries) {
      final pattern = entry.key;
      final matches = switch (pattern) {
        final RegExp re => re.hasMatch(fullUrl) || re.hasMatch(path),
        final String s => fullUrl == s || path == s,
        _ => false,
      };
      if (matches) return entry.value;
    }
    return null;
  }
}

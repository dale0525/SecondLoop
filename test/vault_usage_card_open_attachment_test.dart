import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/features/settings/vault_usage_card.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

Future<void> _pumpUi(WidgetTester tester, {int cycles = 16}) async {
  for (var i = 0; i < cycles; i += 1) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

void main() {
  testWidgets(
      'VaultUsageCard opens grouped video attachment details by root sha',
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
      },
    );

    final backend = _FakeBackend(
      attachment: const Attachment(
        sha256: rootSha,
        mimeType: 'video/mp4',
        path: 'attachments/sha-video-root.bin',
        byteLen: 4096,
        createdAtMs: 1000,
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: CloudAuthScope(
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

    expect(find.byType(AttachmentViewerPage), findsOneWidget);
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
        AppBackendScope(
          backend: _FakeBackend(
            attachment: const Attachment(
              sha256: 'sha-vault-2',
              mimeType: 'text/plain',
              path: 'attachments/sha-vault-2.bin',
              byteLen: 20,
              createdAtMs: 3000,
            ),
          ),
          child: CloudAuthScope(
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
        AppBackendScope(
          backend: _FakeBackend(
            attachment: const Attachment(
              sha256: 'sha-store-2',
              mimeType: 'text/plain',
              path: 'attachments/sha-store-2.bin',
              byteLen: 20,
              createdAtMs: 3000,
            ),
          ),
          child: CloudAuthScope(
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
        AppBackendScope(
          backend: _FakeBackend(
            attachment: const Attachment(
              sha256: 'sha-race-2',
              mimeType: 'text/plain',
              path: 'attachments/sha-race-2.bin',
              byteLen: 20,
              createdAtMs: 3000,
            ),
          ),
          child: CloudAuthScope(
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
    await _pumpUi(tester, cycles: 6);

    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-race-2')),
        findsOneWidget);

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
    await _pumpUi(tester, cycles: 6);

    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-race-2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('vault_usage_attachment_sha-race-1')),
        findsNothing);
  });

  testWidgets('VaultUsageCard deletes grouped video attachment by root sha',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const rootSha = 'sha-video-root';
    const leafSha = 'sha-video-segment';
    const messageId = 'message_1';

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
        RegExp(r'/v1/vaults/uid_1/attachments/sha-video-root$'):
            _FakeHttpResponse.ok(
          jsonEncode(<String, Object?>{
            'deleted': true,
            'sha256': rootSha,
          }),
        ),
      },
    );

    final backend = _FakeBackend(
      attachment: const Attachment(
        sha256: rootSha,
        mimeType: 'video/mp4',
        path: 'attachments/sha-video-root.bin',
        byteLen: 4096,
        createdAtMs: 1000,
      ),
      conversations: const <Conversation>[
        Conversation(
          id: 'conversation_1',
          title: 'Loop',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      messagesByConversationId: const <String, List<Message>>{
        'conversation_1': <Message>[
          Message(
            id: messageId,
            conversationId: 'conversation_1',
            role: 'user',
            content: 'video',
            createdAtMs: 0,
            isMemory: false,
          ),
        ],
      },
      attachmentsByMessageId: const <String, List<Attachment>>{
        messageId: <Attachment>[
          Attachment(
            sha256: rootSha,
            mimeType: 'video/mp4',
            path: 'attachments/sha-video-root.bin',
            byteLen: 4096,
            createdAtMs: 1000,
          ),
        ],
      },
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: CloudAuthScope(
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
    await tester.pumpAndSettle();

    expect(httpClient.deletePaths, ['/v1/vaults/uid_1/attachments/$rootSha']);
    expect(backend.purgedMessageIds, [messageId]);
  });
}

final class _FakeBackend implements AppBackend, AttachmentsBackend {
  _FakeBackend({
    required this.attachment,
    this.conversations = const <Conversation>[],
    this.messagesByConversationId = const <String, List<Message>>{},
    this.attachmentsByMessageId = const <String, List<Attachment>>{},
  });

  final Attachment attachment;
  final List<Conversation> conversations;
  final Map<String, List<Message>> messagesByConversationId;
  final Map<String, List<Attachment>> attachmentsByMessageId;
  final List<String> purgedMessageIds = <String>[];

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async =>
      conversations;

  @override
  Future<List<Message>> listMessages(Uint8List key, String conversationId) =>
      Future<List<Message>>.value(
        messagesByConversationId[conversationId] ?? const <Message>[],
      );

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async =>
      attachmentsByMessageId[messageId] ?? const <Attachment>[];

  @override
  Future<void> purgeMessageAttachments(Uint8List key, String messageId) async {
    purgedMessageIds.add(messageId);
  }

  @override
  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) async {
    if (attachmentSha256 == attachment.sha256) return attachment;
    return null;
  }

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    return Uint8List.fromList(const <int>[1, 2, 3]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

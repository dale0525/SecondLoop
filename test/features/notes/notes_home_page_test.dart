import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/offline_edit/local_edit_store.dart';
import 'package:secondloop/features/notes/notes_home_page.dart';

import '../../test_i18n.dart';

void main() {
  setUp(RuntimeConnectionStore.resetCacheForTests);

  testWidgets(
    'surfaces remote notes 404 instead of treating it as a local-only library',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final oldPlatform = ConnectivityPlatform.instance;
      final fakeConnectivity = _FakeConnectivityPlatform();
      ConnectivityPlatform.instance = fakeConnectivity;
      final store = LocalEditStore.inMemory();
      await store.saveDraft(
        title: 'Local draft',
        body: 'Local body',
        baseRevision: null,
        nowMs: 1000,
      );
      final httpClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://runtime.test/v1/runtime/vaults/uid-1/notes?limit=100',
        );
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response('not found', 404);
      });

      try {
        await tester.pumpWidget(
          wrapWithI18n(
            MaterialApp(
              home: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://runtime.test',
                  modelName: 'cloud',
                ),
                child: NotesHomePage(
                  store: store,
                  noteHttpClient: httpClient,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('HTTP 404'), findsOneWidget);
        expect(find.text('Local draft'), findsNothing);
        expect(find.byKey(const ValueKey('note_list_create_button')),
            findsNothing);
      } finally {
        await store.close();
        await fakeConnectivity.close();
        ConnectivityPlatform.instance = oldPlatform;
      }
    },
  );

  testWidgets('loads managed-pro notes without exposing creation controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final oldPlatform = ConnectivityPlatform.instance;
    final fakeConnectivity = _FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fakeConnectivity;
    final store = LocalEditStore.inMemory();
    const remoteTitle = 'Managed remote note';
    const remoteBody = 'Existing content created through conversation.';
    final httpClient = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://runtime.test/v1/runtime/vaults/uid-1/notes?limit=100',
      );
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 'note-1',
              'title': remoteTitle,
              'body': remoteBody,
              'revision': 'rev-1',
              'updated_at_ms': 1770000000000,
            },
          ],
          'next_cursor': null,
        }),
        200,
      );
    });

    try {
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: CloudAuthScope(
              controller: _CloudAuthController(),
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://runtime.test',
                modelName: 'cloud',
              ),
              child: NotesHomePage(
                store: store,
                noteHttpClient: httpClient,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(remoteTitle), findsOneWidget);
      expect(find.text('Recent Additions'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('note_list_create_button')), findsNothing);
      expect(
          find.byKey(const ValueKey('note_editor_title_field')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await store.close();
      await fakeConnectivity.close();
      ConnectivityPlatform.instance = oldPlatform;
    }
  });

  testWidgets('loads self-managed notes through the stored runtime connection',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final connectionStore = RuntimeConnectionStore();
    await connectionStore.saveConnection(_selfManagedConnection);
    final oldPlatform = ConnectivityPlatform.instance;
    final fakeConnectivity = _FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fakeConnectivity;
    final store = LocalEditStore.inMemory();
    final httpClient = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://self-runtime.test/v1/runtime/vaults/acct-1/notes?limit=100',
      );
      expect(request.headers['authorization'], 'Bearer runtime-token-1');
      return http.Response(
        '{"items":[{"id":"note-1","title":"Remote note","body":"Vault body",'
        '"revision":"rev-1","updated_at_ms":1770000000000}],'
        '"next_cursor":null}',
        200,
      );
    });

    try {
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: NotesHomePage(
              store: store,
              connectionStore: connectionStore,
              noteHttpClient: httpClient,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Remote note'), findsOneWidget);
      expect(find.text('Recent Additions'), findsOneWidget);
    } finally {
      await store.close();
      await fakeConnectivity.close();
      ConnectivityPlatform.instance = oldPlatform;
    }
  });
}

final class _CloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid-1';

  @override
  String? get email => 'user@example.test';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'token-1';

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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}

final class _FakeConnectivityPlatform extends ConnectivityPlatform {
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const <ConnectivityResult>[ConnectivityResult.wifi];

  Future<void> close() async {
    await _controller.close();
  }
}

const _selfManagedConnection = CloudRuntimeConnection(
  profile: CloudRuntimeProfile(
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://self-runtime.test/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    authToken: 'runtime-token-1',
    capabilityManifestId: 'manifest-self-1',
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    vaultId: 'acct-1',
  ),
  manifest: CloudRuntimeManifest(
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://self-runtime.test/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    capabilities: [CloudRuntimeCapability('chat')],
  ),
);

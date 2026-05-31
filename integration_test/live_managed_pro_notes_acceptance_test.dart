import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_auth_store.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';
import 'package:secondloop/core/cloud/runtime_api_client.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_note_client.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/offline_edit/local_edit_store.dart';
import 'package:secondloop/features/notes/notes_home_page.dart';

import '../test/test_i18n.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RuntimeConnectionStore.resetCacheForTests();
  });

  testWidgets(
    'live managed pro account creates a vault note and the library UI reloads it',
    (tester) async {
      final config = _LiveManagedProNotesConfig.fromEnvironment();
      config.validate();

      final authController = CloudAuthControllerImpl(
        identityToolkit: FirebaseIdentityToolkitHttp(
          webApiKey: config.firebaseWebApiKey,
        ),
        store: _MemoryCloudAuthStore(),
      );
      addTearDown(() async {
        await authController.signOut();
        authController.dispose();
      });

      await authController.signInWithEmailPassword(
        email: config.email,
        password: config.password,
      );
      final vaultId = authController.uid?.trim() ?? '';
      expect(vaultId, isNotEmpty);
      expect(await authController.getIdToken(), isNotEmpty);
      final noteClient = _noteClient(
        authController: authController,
        cloudGatewayBaseUrl: config.cloudGatewayBaseUrl,
      );
      addTearDown(noteClient.dispose);
      await noteClient
          .listNotes(vaultId: vaultId, limit: 1)
          .timeout(const Duration(seconds: 60));

      final store = LocalEditStore.inMemory();
      final oldConnectivityPlatform = ConnectivityPlatform.instance;
      final fakeConnectivityPlatform = _FakeConnectivityPlatform();
      ConnectivityPlatform.instance = fakeConnectivityPlatform;
      addTearDown(() async {
        await store.close();
        await fakeConnectivityPlatform.close();
        ConnectivityPlatform.instance = oldConnectivityPlatform;
      });

      final createdAt = DateTime.now().toUtc();
      final uniqueSuffix = createdAt.microsecondsSinceEpoch;
      final title = 'SEC-2 managed pro vault note $uniqueSuffix';
      final body =
          'Dynamic library acceptance note for SEC-2 created at ${createdAt.toIso8601String()}.';

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: CloudAuthScope(
              controller: authController,
              gatewayConfig: CloudGatewayConfig(
                baseUrl: config.cloudGatewayBaseUrl,
                modelName: 'cloud',
              ),
              child: NotesHomePage(store: store),
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('note_list_create_button'))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 90),
        reason: 'managed pro library did not load the note list',
      );

      await tester.tap(find.byKey(const ValueKey('note_list_create_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('note_editor_title_field')),
        title,
      );
      await tester.enterText(
        find.byKey(const ValueKey('note_editor_body_field')),
        body,
      );

      await tester.tap(find.byKey(const ValueKey('note_editor_save_button')));
      final remote = await _waitForRemoteNote(
        tester: tester,
        noteClient: noteClient,
        vaultId: vaultId,
        title: title,
        timeout: const Duration(seconds: 60),
      );
      expect(remote.body, body);
      expect(remote.revision, isNotEmpty);

      final fetched = await noteClient.fetchNote(
        vaultId: vaultId,
        noteId: remote.id,
      );
      expect(fetched.title, title);
      expect(fetched.body, body);
      expect(fetched.revision, remote.revision);
      expect(find.text('Saved'), findsOneWidget);
      debugPrint('SEC-2 managed pro note verified: $title');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<RuntimeNote> _waitForRemoteNote({
  required WidgetTester tester,
  required RuntimeNoteClient noteClient,
  required String vaultId,
  required String title,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 500));
    try {
      final notes = await noteClient.listNotes(vaultId: vaultId, limit: 100);
      for (final note in notes) {
        if (note.title == title) return note;
      }
    } catch (error) {
      lastError = error;
    }
  }
  fail(
    'managed pro library note did not appear in the remote vault list'
    '${lastError == null ? '' : ': $lastError'}',
  );
}

RuntimeNoteClient _noteClient({
  required CloudAuthControllerImpl authController,
  required String cloudGatewayBaseUrl,
}) {
  return RuntimeNoteClient(
    apiClient: RuntimeApiClient(
      connectionLoader: () async {
        final token = (await authController.getIdToken())?.trim() ?? '';
        if (token.isEmpty) return null;
        return CloudRuntimeConnection(
          profile: CloudRuntimeProfile(
            runtimeMode: CloudRuntimeMode.managedPro,
            apiBaseUrl: cloudGatewayBaseUrl,
            authMode: CloudRuntimeAuthMode.hostedSession,
            authToken: token,
            capabilityManifestId: 'managed-pro-runtime',
            manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
          ),
          manifest: CloudRuntimeManifest(
            manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
            runtimeMode: CloudRuntimeMode.managedPro,
            apiBaseUrl: cloudGatewayBaseUrl,
            authMode: CloudRuntimeAuthMode.hostedSession,
            capabilities: CloudRuntimeRequiredCapabilities.all,
            skills: CloudRuntimeKnownSkills.all,
          ),
        );
      },
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(condition(), isTrue, reason: reason);
}

final class _LiveManagedProNotesConfig {
  const _LiveManagedProNotesConfig({
    required this.enabled,
    required this.email,
    required this.password,
    required this.firebaseWebApiKey,
    required this.cloudGatewayBaseUrl,
  });

  final bool enabled;
  final String email;
  final String password;
  final String firebaseWebApiKey;
  final String cloudGatewayBaseUrl;

  factory _LiveManagedProNotesConfig.fromEnvironment() {
    final env = Platform.environment;
    return _LiveManagedProNotesConfig(
      enabled: env['SECONDLOOP_LIVE_MANAGED_PRO_ACCEPTANCE']?.trim() == '1',
      email: env['SECONDLOOP_LIVE_MANAGED_PRO_EMAIL']?.trim() ?? '',
      password: env['SECONDLOOP_LIVE_MANAGED_PRO_PASSWORD']?.trim() ?? '',
      firebaseWebApiKey: _firstNonEmpty([
        env['SECONDLOOP_FIREBASE_WEB_API_KEY'],
        const String.fromEnvironment('SECONDLOOP_FIREBASE_WEB_API_KEY'),
      ]),
      cloudGatewayBaseUrl: _firstNonEmpty([
        env['SECONDLOOP_CLOUD_GATEWAY_BASE_URL'],
        const String.fromEnvironment('SECONDLOOP_CLOUD_GATEWAY_BASE_URL'),
        _envScopedGateway(env),
      ]),
    );
  }

  void validate() {
    final missing = <String>[];
    if (!enabled) missing.add('SECONDLOOP_LIVE_MANAGED_PRO_ACCEPTANCE=1');
    if (email.isEmpty) missing.add('SECONDLOOP_LIVE_MANAGED_PRO_EMAIL');
    if (password.isEmpty) missing.add('SECONDLOOP_LIVE_MANAGED_PRO_PASSWORD');
    if (firebaseWebApiKey.isEmpty) {
      missing.add('SECONDLOOP_FIREBASE_WEB_API_KEY');
    }
    if (cloudGatewayBaseUrl.isEmpty) {
      missing.add('SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING/PROD');
    }
    if (missing.isNotEmpty) {
      fail(
        'Missing live managed pro notes configuration: ${missing.join(', ')}',
      );
    }
  }
}

String _envScopedGateway(Map<String, String> env) {
  final cloudEnv = env['SECONDLOOP_CLOUD_ENV']?.trim().toLowerCase();
  if (cloudEnv == 'staging' || cloudEnv == 'stage') {
    return env['SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING']?.trim() ?? '';
  }
  if (cloudEnv == 'prod' || cloudEnv == 'production') {
    return env['SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD']?.trim() ?? '';
  }
  return '';
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

final class _MemoryCloudAuthStore implements CloudAuthStore {
  CloudAuthStoredSession? _session;

  @override
  Future<void> clear() async {
    _session = null;
  }

  @override
  Future<CloudAuthStoredSession?> load() async {
    return _session;
  }

  @override
  Future<void> save(CloudAuthStoredSession session) async {
    _session = session;
  }
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

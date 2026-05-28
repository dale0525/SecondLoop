import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/runtime_api_client.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_note_client.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';

void main() {
  test('saveNote sends PUT bearer request and parses success', () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(
        request.url.toString(),
        'https://runtime.test/v1/runtime/vaults/vault-1/notes/note-1',
      );
      expect(request.headers['authorization'], 'Bearer runtime-token-1');
      expect(request.headers['accept'], 'application/json');

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['title'], 'Meeting notes');
      expect(body['body'], 'Plain text body');
      expect(body['base_revision'], 'rev-1');

      return http.Response(
        jsonEncode({
          'id': 'note-1',
          'title': 'Meeting notes',
          'body': 'Plain text body',
          'revision': 'rev-2',
          'updated_at_ms': 1770000000000,
        }),
        200,
      );
    });

    final client = _runtimeNoteClient(httpClient);

    final note = await client.saveNote(
      vaultId: 'vault-1',
      noteId: 'note-1',
      title: 'Meeting notes',
      body: 'Plain text body',
      baseRevision: 'rev-1',
    );

    expect(note.id, 'note-1');
    expect(note.title, 'Meeting notes');
    expect(note.body, 'Plain text body');
    expect(note.revision, 'rev-2');
    expect(note.updatedAtMs, 1770000000000);
  });

  test('saveNote URL-encodes vault and note path segments', () async {
    final httpClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://runtime.test/v1/runtime/vaults/vault%2Fwith%20space/notes/'
        'note%2Fwith%20space',
      );
      return http.Response(
        jsonEncode({
          'id': 'note/with space',
          'title': 'Title',
          'body': 'Body',
          'revision': 'rev-1',
          'updated_at_ms': 1770000000000,
        }),
        200,
      );
    });

    final client = _runtimeNoteClient(httpClient);

    final note = await client.saveNote(
      vaultId: 'vault/with space',
      noteId: 'note/with space',
      title: 'Title',
      body: 'Body',
      baseRevision: null,
    );

    expect(note.id, 'note/with space');
  });

  test('saveNote rejects malformed success note fields', () async {
    final httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'id': 'note-1',
          'title': ['not a string'],
          'body': 'Body',
          'revision': 'rev-1',
          'updated_at_ms': 1.5,
        }),
        200,
      );
    });

    final client = _runtimeNoteClient(httpClient);

    await expectLater(
      client.saveNote(
        vaultId: 'vault-1',
        noteId: 'note-1',
        title: 'Title',
        body: 'Body',
        baseRevision: null,
      ),
      throwsFormatException,
    );
  });

  test('saveNote rejects non-int updated timestamp fields', () async {
    for (final malformedTimestamp in <Object>['1770000000000', 1.5]) {
      final httpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'note-1',
            'title': 'Title',
            'body': 'Body',
            'revision': 'rev-1',
            'updated_at_ms': malformedTimestamp,
          }),
          200,
        );
      });

      final client = _runtimeNoteClient(httpClient);

      await expectLater(
        client.saveNote(
          vaultId: 'vault-1',
          noteId: 'note-1',
          title: 'Title',
          body: 'Body',
          baseRevision: null,
        ),
        throwsFormatException,
      );
    }
  });

  test('saveNote throws conflict exception with remote note', () async {
    final httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': 'revision_conflict',
          'remote': {
            'id': 'note-1',
            'title': 'Remote title',
            'body': 'Remote body',
            'revision': 'rev-remote',
            'updated_at_ms': 1770000000100,
          },
        }),
        409,
      );
    });

    final client = _runtimeNoteClient(httpClient);

    await expectLater(
      client.saveNote(
        vaultId: 'vault-1',
        noteId: 'note-1',
        title: 'Local title',
        body: 'Local body',
        baseRevision: 'rev-stale',
      ),
      throwsA(
        isA<RuntimeNoteConflictException>()
            .having((error) => error.remote.id, 'remote id', 'note-1')
            .having(
              (error) => error.remote.title,
              'remote title',
              'Remote title',
            )
            .having(
              (error) => error.remote.revision,
              'remote revision',
              'rev-remote',
            ),
      ),
    );
  });

  test('fetchNote sends GET bearer request and parses note', () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://runtime.test/v1/runtime/vaults/vault-1/notes/note-1',
      );
      expect(request.headers['authorization'], 'Bearer runtime-token-1');
      return http.Response(
        jsonEncode({
          'id': 'note-1',
          'title': 'Remote title',
          'body': 'Remote body',
          'revision': 'rev-3',
          'updated_at_ms': 1770000000000,
        }),
        200,
      );
    });

    final client = _runtimeNoteClient(httpClient);

    final note = await client.fetchNote(vaultId: 'vault-1', noteId: 'note-1');

    expect(note.title, 'Remote title');
    expect(note.body, 'Remote body');
    expect(note.revision, 'rev-3');
  });

  test('listNotes sends GET bearer request and parses ordered notes', () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://runtime.test/v1/runtime/vaults/vault-1/notes?limit=50',
      );
      expect(request.headers['authorization'], 'Bearer runtime-token-1');
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 'note-2',
              'title': 'Newer',
              'body': 'Newer body',
              'revision': 'rev-2',
              'updated_at_ms': 1770000000200,
            },
            {
              'id': 'note-1',
              'title': 'Older',
              'body': 'Older body',
              'revision': 'rev-1',
              'updated_at_ms': 1770000000100,
            },
          ],
          'next_cursor': null,
        }),
        200,
      );
    });

    final client = _runtimeNoteClient(httpClient);

    final notes = await client.listNotes(vaultId: 'vault-1', limit: 50);

    expect(notes.map((note) => note.id), ['note-2', 'note-1']);
    expect(notes.first.title, 'Newer');
    expect(notes.first.revision, 'rev-2');
  });

  test('listNotes throws typed HTTP exception for non-success response',
      () async {
    final httpClient = MockClient((request) async {
      return http.Response('not found', 404);
    });
    final client = _runtimeNoteClient(httpClient);

    await expectLater(
      client.listNotes(vaultId: 'vault-1'),
      throwsA(
        isA<RuntimeNoteHttpException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.body, 'body', 'not found'),
      ),
    );
  });

  test('deleteNote sends DELETE with encoded base revision', () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(
        request.url.toString(),
        'https://runtime.test/v1/runtime/vaults/vault-1/notes/note-1'
        '?base_revision=rev%2F1',
      );
      expect(request.headers['authorization'], 'Bearer runtime-token-1');
      return http.Response('', 204);
    });

    final client = _runtimeNoteClient(httpClient);

    await client.deleteNote(
      vaultId: 'vault-1',
      noteId: 'note-1',
      baseRevision: 'rev/1',
    );
  });
}

RuntimeNoteClient _runtimeNoteClient(http.Client httpClient) {
  return RuntimeNoteClient(
    apiClient: RuntimeApiClient(
      connectionLoader: () async => _runtimeConnection,
      httpClient: httpClient,
    ),
  );
}

const _runtimeConnection = CloudRuntimeConnection(
  profile: CloudRuntimeProfile(
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://runtime.test/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    authToken: 'runtime-token-1',
    capabilityManifestId: 'manifest-self-1',
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    vaultId: 'vault-1',
  ),
  manifest: CloudRuntimeManifest(
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://runtime.test/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    capabilities: [CloudRuntimeCapability('chat')],
  ),
);

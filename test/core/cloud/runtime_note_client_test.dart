import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/runtime_note_client.dart';

void main() {
  test('saveNote sends PUT bearer request and parses success', () async {
    final httpClient = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(
        request.url.toString(),
        'https://vault.test/v1/vaults/vault-1/notes/note-1',
      );
      expect(request.headers['authorization'], 'Bearer token-1');
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

    final client = RuntimeNoteClient(
      managedVaultBaseUrl: 'https://vault.test',
      idToken: 'token-1',
      httpClient: httpClient,
    );

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

    final client = RuntimeNoteClient(
      managedVaultBaseUrl: 'https://vault.test',
      idToken: 'token-1',
      httpClient: httpClient,
    );

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
}

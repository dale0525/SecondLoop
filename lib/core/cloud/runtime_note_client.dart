import 'package:flutter/foundation.dart';

import 'runtime_api_client.dart';

@immutable
class RuntimeNote {
  const RuntimeNote({
    required this.id,
    required this.title,
    required this.body,
    required this.revision,
    required this.updatedAtMs,
  });

  final String id;
  final String title;
  final String body;
  final String revision;
  final int updatedAtMs;
}

final class RuntimeNoteConflictException implements Exception {
  const RuntimeNoteConflictException({
    required this.remote,
  });

  final RuntimeNote remote;

  @override
  String toString() {
    return 'RuntimeNoteConflictException(remote: ${remote.id}, '
        'revision: ${remote.revision})';
  }
}

final class RuntimeNoteHttpException implements Exception {
  const RuntimeNoteHttpException({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  @override
  String toString() {
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) return 'HTTP $statusCode';
    return 'HTTP $statusCode: $normalizedBody';
  }
}

final class RuntimeNoteClient {
  RuntimeNoteClient({
    RuntimeApiClient? apiClient,
  }) : _apiClient = apiClient ?? RuntimeApiClient();

  final RuntimeApiClient _apiClient;

  Future<RuntimeNote> saveNote({
    required String vaultId,
    required String noteId,
    required String title,
    required String body,
    required String? baseRevision,
  }) async {
    final response = await _apiClient.requestJson(
      method: 'PUT',
      path: _notePath(vaultId: vaultId, noteId: noteId),
      headers: <String, String>{
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      body: <String, Object?>{
        'title': title,
        'body': body,
        'base_revision': baseRevision,
      },
    );

    final decoded = response.tryDecodeObject();
    if (response.statusCode == 409) {
      final remote = decoded?['remote'];
      if (remote is Map) {
        throw RuntimeNoteConflictException(
          remote: _noteFromJson(Map<String, Object?>.from(remote)),
        );
      }
      throw const FormatException('invalid_runtime_note_conflict');
    }

    _throwIfHttpError(response);

    if (decoded == null) {
      throw const FormatException('invalid_runtime_note_response');
    }
    return _noteFromJson(decoded);
  }

  Future<RuntimeNote> fetchNote({
    required String vaultId,
    required String noteId,
  }) async {
    final response = await _apiClient.requestJson(
      method: 'GET',
      path: _notePath(vaultId: vaultId, noteId: noteId),
      headers: <String, String>{
        'accept': 'application/json',
      },
    );

    _throwIfHttpError(response);

    final decoded = response.tryDecodeObject();
    if (decoded == null) {
      throw const FormatException('invalid_runtime_note_response');
    }
    return _noteFromJson(decoded);
  }

  Future<List<RuntimeNote>> listNotes({
    required String vaultId,
    int limit = 100,
  }) async {
    final response = await _apiClient.requestJson(
      method: 'GET',
      path: _noteListPath(vaultId: vaultId, limit: limit),
      headers: <String, String>{
        'accept': 'application/json',
      },
    );

    _throwIfHttpError(response);

    final decoded = response.tryDecodeObject();
    final rawItems = decoded?['items'];
    if (rawItems is! List) {
      throw const FormatException('invalid_runtime_note_list_response');
    }
    return rawItems.map((raw) {
      if (raw is! Map) {
        throw const FormatException('invalid_runtime_note_list_item');
      }
      return _noteFromJson(Map<String, Object?>.from(raw));
    }).toList(growable: false);
  }

  Future<void> deleteNote({
    required String vaultId,
    required String noteId,
    required String? baseRevision,
  }) async {
    final response = await _apiClient.requestJson(
      method: 'DELETE',
      path: _notePath(
        vaultId: vaultId,
        noteId: noteId,
        queryParameters: <String, String>{
          if (baseRevision != null) 'base_revision': baseRevision,
        },
      ),
      headers: <String, String>{
        'accept': 'application/json',
      },
    );

    if (response.statusCode == 409) {
      final decoded = response.tryDecodeObject();
      final remote = decoded?['remote'];
      if (remote is Map) {
        throw RuntimeNoteConflictException(
          remote: _noteFromJson(Map<String, Object?>.from(remote)),
        );
      }
      throw const FormatException('invalid_runtime_note_conflict');
    }

    _throwIfHttpError(response);
  }

  void dispose() {
    _apiClient.dispose();
  }
}

void _throwIfHttpError(RuntimeApiJsonResponse response) {
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  throw RuntimeNoteHttpException(
    statusCode: response.statusCode,
    body: response.body,
  );
}

RuntimeNote _noteFromJson(Map<String, Object?> json) {
  final id = _requiredString(json, 'id').trim();
  final title = _requiredString(json, 'title');
  final body = _requiredString(json, 'body');
  final revision = _requiredString(json, 'revision').trim();
  final updatedAtMs = _requiredInt(json, 'updated_at_ms');
  if (id.isEmpty || revision.isEmpty) {
    throw const FormatException('invalid_runtime_note_fields');
  }
  return RuntimeNote(
    id: id,
    title: title,
    body: body,
    revision: revision,
    updatedAtMs: updatedAtMs,
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw const FormatException('invalid_runtime_note_fields');
}

String _noteListPath({
  required String vaultId,
  required int limit,
}) {
  final query = Uri(queryParameters: <String, String>{
    'limit': '$limit',
  }).query;
  return '/v1/runtime/vaults/${Uri.encodeComponent(vaultId)}/notes?$query';
}

String _notePath({
  required String vaultId,
  required String noteId,
  Map<String, String> queryParameters = const <String, String>{},
}) {
  final query = queryParameters.isEmpty
      ? ''
      : '?${Uri(queryParameters: queryParameters).query}';
  return '/v1/runtime/vaults/${Uri.encodeComponent(vaultId)}/notes/'
      '${Uri.encodeComponent(noteId)}$query';
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw const FormatException('invalid_runtime_note_fields');
}

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_json_client.dart';

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

final class RuntimeNoteClient {
  RuntimeNoteClient({
    required String managedVaultBaseUrl,
    required String idToken,
    http.Client? httpClient,
  })  : _managedVaultBaseUrl = managedVaultBaseUrl,
        _idToken = idToken,
        _httpClient = HttpJsonClient(client: httpClient);

  final String _managedVaultBaseUrl;
  final String _idToken;
  final HttpJsonClient _httpClient;

  Future<RuntimeNote> saveNote({
    required String vaultId,
    required String noteId,
    required String title,
    required String body,
    required String? baseRevision,
  }) async {
    final uri = _resolveVaultUri(
      _managedVaultBaseUrl,
      '/v1/vaults/${Uri.encodeComponent(vaultId)}/notes/'
      '${Uri.encodeComponent(noteId)}',
    );
    final response = await _httpClient.putJson(
      uri,
      headers: <String, String>{
        'authorization': 'Bearer $_idToken',
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    if (decoded == null) {
      throw const FormatException('invalid_runtime_note_response');
    }
    return _noteFromJson(decoded);
  }

  void dispose() {
    _httpClient.close();
  }
}

RuntimeNote _noteFromJson(Map<String, Object?> json) {
  final id = '${json['id'] ?? ''}'.trim();
  final title = '${json['title'] ?? ''}';
  final body = '${json['body'] ?? ''}';
  final revision = '${json['revision'] ?? ''}'.trim();
  final updatedAtMs = _parseInt(json['updated_at_ms']);
  if (id.isEmpty || revision.isEmpty || updatedAtMs == null) {
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

Uri _resolveVaultUri(String baseUrl, String path) {
  try {
    return Uri.parse(baseUrl).resolve(path);
  } catch (_) {
    throw FormatException('invalid_managed_vault_base_url', baseUrl);
  }
}

int? _parseInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value);
  return null;
}

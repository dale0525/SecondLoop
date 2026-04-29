import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_json_client.dart';

@immutable
class AgentDigestMeta {
  const AgentDigestMeta({
    required this.exists,
    required this.version,
    required this.byteLen,
    required this.generatedAtMs,
    required this.deviceId,
    required this.updatedAtMs,
    this.deletedAtMs,
  });

  const AgentDigestMeta.empty({this.deletedAtMs})
      : exists = false,
        version = null,
        byteLen = null,
        generatedAtMs = null,
        deviceId = null,
        updatedAtMs = null;

  final bool exists;
  final String? version;
  final int? byteLen;
  final int? generatedAtMs;
  final String? deviceId;
  final int? updatedAtMs;
  final int? deletedAtMs;

  factory AgentDigestMeta.fromJson(Map<String, dynamic> json) {
    final exists = json['exists'] == true;
    if (!exists) {
      return AgentDigestMeta.empty(
        deletedAtMs: _parseInt(json['deleted_at_ms']),
      );
    }
    return AgentDigestMeta(
      exists: true,
      version: _parseString(json['version']),
      byteLen: _parseInt(json['byte_len']),
      generatedAtMs: _parseInt(json['generated_at_ms']),
      deviceId: _parseString(json['device_id']),
      updatedAtMs: _parseInt(json['updated_at_ms']),
    );
  }
}

abstract interface class AgentDigestApi {
  Future<AgentDigestMeta> fetchMeta({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  });

  Future<AgentDigestMeta> uploadDigest({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    required Map<String, Object?> digest,
  });

  Future<bool> deleteDigest({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  });
}

final class AgentDigestClient implements AgentDigestApi {
  AgentDigestClient({http.Client? httpClient})
      : _httpClient = HttpJsonClient(client: httpClient);

  final HttpJsonClient _httpClient;

  @override
  Future<AgentDigestMeta> fetchMeta({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final response = await _httpClient.get(
      _resolveVaultUri(
        managedVaultBaseUrl,
        '/v1/vaults/$vaultId/agent-digest/meta',
      ),
      headers: _headers(idToken),
    );
    return _parseMetaResponse(response);
  }

  @override
  Future<AgentDigestMeta> uploadDigest({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    required Map<String, Object?> digest,
  }) async {
    final response = await _httpClient.putJson(
      _resolveVaultUri(
        managedVaultBaseUrl,
        '/v1/vaults/$vaultId/agent-digest',
      ),
      headers: _headers(idToken),
      body: digest,
    );
    return _parseMetaResponse(response);
  }

  @override
  Future<bool> deleteDigest({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final response = await _httpClient.delete(
      _resolveVaultUri(
        managedVaultBaseUrl,
        '/v1/vaults/$vaultId/agent-digest',
      ),
      headers: _headers(idToken),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = response.tryDecodeObject();
    return decoded?['deleted'] == true;
  }

  void dispose() {
    _httpClient.close();
  }
}

AgentDigestMeta _parseMetaResponse(HttpJsonResponse response) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }
  final decoded = response.tryDecodeObject();
  if (decoded == null) {
    throw const FormatException('invalid_agent_digest_meta_response');
  }
  return AgentDigestMeta.fromJson(decoded);
}

Map<String, String> _headers(String idToken) {
  return <String, String>{
    'authorization': 'Bearer $idToken',
    'accept': 'application/json',
    'content-type': 'application/json',
  };
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

String? _parseString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

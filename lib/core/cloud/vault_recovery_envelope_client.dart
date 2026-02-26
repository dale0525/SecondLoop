import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class VaultRecoveryEnvelopeClient {
  VaultRecoveryEnvelopeClient({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<String?> fetchRecoveryEnvelope({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Vault recovery envelope is not supported on web',
      );
    }

    Uri uri;
    try {
      uri = Uri.parse(managedVaultBaseUrl)
          .resolve('/v1/vaults/$vaultId/recovery-envelope');
    } catch (_) {
      throw FormatException(
        'invalid_managed_vault_base_url',
        managedVaultBaseUrl,
      );
    }

    final req = await _httpClient.getUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final resp = await req.close();
    final text = await utf8.decodeStream(resp);

    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: $text');
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('invalid_recovery_envelope_response');
    }
    final envelopeJson = '${decoded['envelope_json'] ?? ''}'.trim();
    if (envelopeJson.isEmpty) {
      throw const FormatException('invalid_recovery_envelope_payload');
    }
    return envelopeJson;
  }

  Future<void> putRecoveryEnvelope({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    required String envelopeJson,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Vault recovery envelope is not supported on web',
      );
    }

    final payload = envelopeJson.trim();
    if (payload.isEmpty) {
      throw ArgumentError('envelopeJson must not be empty');
    }

    Uri uri;
    try {
      uri = Uri.parse(managedVaultBaseUrl)
          .resolve('/v1/vaults/$vaultId/recovery-envelope');
    } catch (_) {
      throw FormatException(
        'invalid_managed_vault_base_url',
        managedVaultBaseUrl,
      );
    }

    final req = await _httpClient.putUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.add(
      utf8.encode(jsonEncode({'envelope_json': payload})),
    );

    final resp = await req.close();
    final text = await utf8.decodeStream(resp);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: $text');
    }
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}

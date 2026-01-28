import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class VaultUsageSummary {
  const VaultUsageSummary({
    required this.totalBytesUsed,
    required this.attachmentsBytesUsed,
    required this.opsBytesUsed,
    required this.otherBytesUsed,
    required this.limitBytes,
  });

  final int totalBytesUsed;
  final int attachmentsBytesUsed;
  final int opsBytesUsed;
  final int otherBytesUsed;
  final int? limitBytes;
}

final class VaultUsageClient {
  VaultUsageClient({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<VaultUsageSummary> fetchVaultUsageSummary({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    if (kIsWeb) throw UnsupportedError('Vault usage is not supported on web');

    Uri uri;
    try {
      uri = Uri.parse(managedVaultBaseUrl).resolve('/v1/vaults/$vaultId/usage');
    } catch (_) {
      throw FormatException(
          'invalid_managed_vault_base_url', managedVaultBaseUrl);
    }

    final req = await _httpClient.getUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final resp = await req.close();
    final text = await utf8.decodeStream(resp);

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: $text');
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('invalid_vault_usage_response');
    }

    final totalBytesUsed = _parseInt(decoded['total_bytes_used']);
    final attachmentsBytesUsed = _parseInt(decoded['attachments_bytes_used']);
    final opsBytesUsed = _parseInt(decoded['ops_bytes_used']);
    final otherBytesUsed = _parseInt(decoded['other_bytes_used']);
    final limitBytes = _parseInt(decoded['limit_bytes']);

    if (totalBytesUsed == null ||
        attachmentsBytesUsed == null ||
        opsBytesUsed == null ||
        otherBytesUsed == null) {
      throw const FormatException('invalid_vault_usage_response_fields');
    }

    return VaultUsageSummary(
      totalBytesUsed: totalBytesUsed,
      attachmentsBytesUsed: attachmentsBytesUsed,
      opsBytesUsed: opsBytesUsed,
      otherBytesUsed: otherBytesUsed,
      limitBytes: limitBytes,
    );
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}

int? _parseInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value);
  return null;
}

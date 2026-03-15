import 'package:flutter/foundation.dart';

import 'http_json_client.dart';

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
  VaultUsageClient({Object? httpClient})
      : _httpClient = HttpJsonClient(client: httpClient);

  final HttpJsonClient _httpClient;

  Future<VaultUsageSummary> fetchVaultUsageSummary({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final uri =
        _resolveVaultUri(managedVaultBaseUrl, '/v1/vaults/$vaultId/usage');
    final response = await _httpClient.get(
      uri,
      headers: <String, String>{
        'authorization': 'Bearer $idToken',
        'accept': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = response.tryDecodeObject();
    if (decoded == null) {
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
    _httpClient.close();
  }
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

import 'package:flutter/foundation.dart';

import 'http_json_client.dart';

@immutable
class CloudUsageSummary {
  const CloudUsageSummary({
    required this.askAiUsagePercent,
    required this.embeddingsUsagePercent,
    required this.resetAtMs,
  });

  final int askAiUsagePercent;
  final int embeddingsUsagePercent;
  final int? resetAtMs;
}

final class CloudUsageClient {
  CloudUsageClient({Object? httpClient})
      : _httpClient = HttpJsonClient(client: httpClient);

  final HttpJsonClient _httpClient;

  Future<CloudUsageSummary> fetchUsageSummary({
    required String cloudGatewayBaseUrl,
    required String idToken,
  }) async {
    final uri = _resolveUri(cloudGatewayBaseUrl, '/v1/usage');
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
      throw const FormatException('invalid_usage_response');
    }

    final usagePercent = _parseInt(decoded['usage_percent']);
    final askAiUsagePercent =
        _parseInt(decoded['ask_ai_usage_percent']) ?? usagePercent;
    final embeddingsUsagePercent =
        _parseInt(decoded['embeddings_usage_percent']) ?? 0;
    final resetAtMs = _parseInt(decoded['reset_at_ms']);

    if (askAiUsagePercent == null) {
      throw const FormatException('invalid_usage_response_fields');
    }

    return CloudUsageSummary(
      askAiUsagePercent: askAiUsagePercent,
      embeddingsUsagePercent: embeddingsUsagePercent,
      resetAtMs: resetAtMs,
    );
  }

  void dispose() {
    _httpClient.close();
  }
}

Uri _resolveUri(String baseUrl, String path) {
  try {
    return Uri.parse(baseUrl).resolve(path);
  } catch (_) {
    throw FormatException('invalid_gateway_base_url', baseUrl);
  }
}

int? _parseInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value);
  return null;
}

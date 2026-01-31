import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
  CloudUsageClient({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<CloudUsageSummary> fetchUsageSummary({
    required String cloudGatewayBaseUrl,
    required String idToken,
  }) async {
    if (kIsWeb) throw UnsupportedError('Cloud usage is not supported on web');

    Uri uri;
    try {
      uri = Uri.parse(cloudGatewayBaseUrl).resolve('/v1/usage');
    } catch (_) {
      throw FormatException('invalid_gateway_base_url', cloudGatewayBaseUrl);
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
    _httpClient.close(force: true);
  }
}

int? _parseInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value);
  return null;
}

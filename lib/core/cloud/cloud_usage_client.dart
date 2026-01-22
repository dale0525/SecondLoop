import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class CloudUsageSummary {
  const CloudUsageSummary({
    required this.usagePercent,
    required this.resetAtMs,
  });

  final int usagePercent;
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
    final resetAtMs = _parseInt(decoded['reset_at_ms']);

    if (usagePercent == null) {
      throw const FormatException('invalid_usage_response_fields');
    }

    return CloudUsageSummary(
      usagePercent: usagePercent,
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

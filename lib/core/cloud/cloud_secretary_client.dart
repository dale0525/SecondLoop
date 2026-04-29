import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_json_client.dart';

@immutable
class CloudSecretaryPlanningItem {
  const CloudSecretaryPlanningItem({
    required this.id,
    required this.todoId,
    required this.title,
    required this.reason,
    required this.requiresConfirmation,
    this.dueAtMs,
    this.section = 'focus',
  });

  final String id;
  final String todoId;
  final String title;
  final String reason;
  final bool requiresConfirmation;
  final int? dueAtMs;
  final String section;

  factory CloudSecretaryPlanningItem.fromJson(Map<String, dynamic> json) {
    return CloudSecretaryPlanningItem(
      id: _parseString(json['id']) ?? '',
      todoId: _parseString(json['todo_id']) ?? '',
      title: _parseString(json['title']) ?? '',
      reason: _parseString(json['reason']) ?? '',
      requiresConfirmation: json['requires_confirmation'] == true,
      dueAtMs: _parseInt(json['due_at_ms']),
      section: _parseString(json['section']) ?? 'focus',
    );
  }
}

@immutable
class CloudSecretaryPlanningResult {
  const CloudSecretaryPlanningResult({
    required this.id,
    required this.kind,
    required this.status,
    required this.title,
    required this.body,
    required this.generatedAtMs,
    required this.digestGeneratedAtMs,
    required this.skipReason,
    required this.items,
  });

  final String id;
  final String kind;
  final String status;
  final String title;
  final String body;
  final int generatedAtMs;
  final int? digestGeneratedAtMs;
  final String? skipReason;
  final List<CloudSecretaryPlanningItem> items;

  factory CloudSecretaryPlanningResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return CloudSecretaryPlanningResult(
      id: _parseString(json['id']) ?? '',
      kind: _parseString(json['kind']) ?? 'daily_plan',
      status: _parseString(json['status']) ?? 'ready',
      title: _parseString(json['title']) ?? '',
      body: _parseString(json['body']) ?? '',
      generatedAtMs: _parseInt(json['generated_at_ms']) ?? 0,
      digestGeneratedAtMs: _parseInt(json['digest_generated_at_ms']),
      skipReason: _parseString(json['skip_reason']),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => CloudSecretaryPlanningItem.fromJson(
                    item.map((key, value) => MapEntry('$key', value)),
                  ))
              .toList(growable: false)
          : const <CloudSecretaryPlanningItem>[],
    );
  }
}

final class CloudSecretaryClient {
  CloudSecretaryClient({http.Client? httpClient})
      : _httpClient = HttpJsonClient(client: httpClient);

  final HttpJsonClient _httpClient;

  Future<List<CloudSecretaryPlanningResult>> fetchPlanningResults({
    required String cloudGatewayBaseUrl,
    required String idToken,
    int? sinceMs,
  }) async {
    final query = <String, String>{};
    if (sinceMs != null) query['since_ms'] = '$sinceMs';
    final uri = _resolveGatewayUri(
      cloudGatewayBaseUrl,
      '/v1/secretary/planning-results',
    ).replace(queryParameters: query.isEmpty ? null : query);

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
    final rawResults = decoded?['results'];
    if (rawResults is! List) {
      throw const FormatException('invalid_cloud_secretary_results');
    }
    return rawResults
        .whereType<Map>()
        .map((result) => CloudSecretaryPlanningResult.fromJson(
              result.map((key, value) => MapEntry('$key', value)),
            ))
        .toList(growable: false);
  }

  void dispose() {
    _httpClient.close();
  }
}

Uri _resolveGatewayUri(String baseUrl, String path) {
  try {
    return Uri.parse(baseUrl).resolve(path);
  } catch (_) {
    throw FormatException('invalid_cloud_gateway_base_url', baseUrl);
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

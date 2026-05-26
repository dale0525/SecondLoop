import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

import 'local_qa_worker_script.dart';
import 'resource_plan.dart';

final class CloudflareRuntimeResourceNames {
  const CloudflareRuntimeResourceNames({
    required this.prefix,
    required this.workerNames,
    required this.d1DatabaseName,
    required this.kvNamespaceTitle,
    required this.r2BucketName,
  });

  final String prefix;
  final List<String> workerNames;
  final String d1DatabaseName;
  final String kvNamespaceTitle;
  final String r2BucketName;

  List<String> get resourceNames => [
        d1DatabaseName,
        kvNamespaceTitle,
        r2BucketName,
      ];
}

final class CloudflareRuntimeResourcesClient {
  CloudflareRuntimeResourcesClient({
    required this.accountId,
    required this.apiToken,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final String accountId;
  final String apiToken;
  final HttpClient _httpClient;

  Future<String> deployLocalQaRuntime(
    SelfManagedSetupRequest request,
    SelfManagedRuntimeResourcePlan plan,
  ) async {
    final names = buildCloudflareRuntimeResourceNames(
      request,
      plan,
      cloudflareAccountId: accountId,
    );
    final d1Id = await _ensureD1Database(names.d1DatabaseName);
    final kvId = await _ensureKvNamespace(names.kvNamespaceTitle);
    await _ensureR2Bucket(names.r2BucketName);
    final subdomain = await _workersSubdomain();
    for (final workerName in names.workerNames) {
      await _uploadWorkerScript(
        workerName: workerName,
        d1DatabaseId: d1Id,
        kvNamespaceId: kvId,
        r2BucketName: names.r2BucketName,
        request: request,
      );
    }
    final apiBaseUrl =
        'https://${names.workerNames.first}.$subdomain.workers.dev/';
    await _runHealthCheck(apiBaseUrl);
    return apiBaseUrl;
  }

  Future<SelfManagedRuntimeUninstallResult> uninstallLocalQaRuntime(
    SelfManagedRuntimeUninstallRequest request,
    SelfManagedRuntimeResourcePlan plan,
  ) async {
    final names = buildCloudflareRuntimeResourceNames(
      request,
      plan,
      cloudflareAccountId: accountId,
    );
    final removedWorkers = <String>[];
    for (final workerName in names.workerNames) {
      if (await _deleteWorkerScript(workerName)) {
        removedWorkers.add(workerName);
      }
    }
    final removedResources = <String>[];
    final d1Id = await _findD1DatabaseId(names.d1DatabaseName);
    if (d1Id != null && await _deleteD1Database(d1Id)) {
      removedResources.add(names.d1DatabaseName);
    }
    final kvId = await _findKvNamespaceId(names.kvNamespaceTitle);
    if (kvId != null && await _deleteKvNamespace(kvId)) {
      removedResources.add(names.kvNamespaceTitle);
    }
    if (await _deleteR2Bucket(names.r2BucketName)) {
      removedResources.add(names.r2BucketName);
    }
    return SelfManagedRuntimeUninstallResult(
      ok: true,
      runtimeMode: 'self_managed',
      cloudflareAccountId: accountId,
      removedWorkers: removedWorkers,
      removedBindings: removedResources,
      removedSecrets: plan.secrets,
    );
  }

  Future<String> _ensureD1Database(String name) async {
    final existing = await _findD1DatabaseId(name);
    if (existing != null) return existing;
    final result = await _requestJson(
      'POST',
      '/accounts/$accountId/d1/database',
      body: <String, Object?>{'name': name},
    );
    final id = _stringField(_asMap(result), ['uuid', 'id']);
    if (id == null) {
      throw const LocalRuntimeHelperException(
        'cloudflare_d1_create_failed',
        'Cloudflare D1 create response did not include an id.',
      );
    }
    return id;
  }

  Future<String?> _findD1DatabaseId(String name) async {
    final result = await _requestJson(
      'GET',
      '/accounts/$accountId/d1/database?name=${Uri.encodeQueryComponent(name)}',
    );
    final databases = _asList(result);
    for (final database in databases) {
      if (database is Map && '${database['name'] ?? ''}' == name) {
        return _stringField(database, ['uuid', 'id']);
      }
    }
    return null;
  }

  Future<bool> _deleteD1Database(String id) async {
    await _requestJson('DELETE', '/accounts/$accountId/d1/database/$id');
    return true;
  }

  Future<String> _ensureKvNamespace(String title) async {
    final existing = await _findKvNamespaceId(title);
    if (existing != null) return existing;
    final result = await _requestJson(
      'POST',
      '/accounts/$accountId/storage/kv/namespaces',
      body: <String, Object?>{'title': title},
    );
    final id = _stringField(_asMap(result), ['id']);
    if (id == null) {
      throw const LocalRuntimeHelperException(
        'cloudflare_kv_create_failed',
        'Cloudflare KV create response did not include an id.',
      );
    }
    return id;
  }

  Future<String?> _findKvNamespaceId(String title) async {
    final result = await _requestJson(
      'GET',
      '/accounts/$accountId/storage/kv/namespaces?per_page=1000',
    );
    final namespaces = _asList(result);
    for (final namespace in namespaces) {
      if (namespace is Map && '${namespace['title'] ?? ''}' == title) {
        return _stringField(namespace, ['id']);
      }
    }
    return null;
  }

  Future<bool> _deleteKvNamespace(String id) async {
    await _requestJson(
      'DELETE',
      '/accounts/$accountId/storage/kv/namespaces/$id',
    );
    return true;
  }

  Future<void> _ensureR2Bucket(String name) async {
    if (await _r2BucketExists(name)) return;
    await _requestJson(
      'POST',
      '/accounts/$accountId/r2/buckets',
      body: <String, Object?>{'name': name},
    );
  }

  Future<bool> _r2BucketExists(String name) async {
    try {
      await _requestJson('GET', '/accounts/$accountId/r2/buckets/$name');
      return true;
    } on LocalRuntimeHelperException catch (error) {
      if (error.code == 'cloudflare_api_not_found') return false;
      rethrow;
    }
  }

  Future<bool> _deleteR2Bucket(String name) async {
    try {
      await _requestJson('DELETE', '/accounts/$accountId/r2/buckets/$name');
      return true;
    } on LocalRuntimeHelperException catch (error) {
      if (error.code == 'cloudflare_api_not_found') return false;
      rethrow;
    }
  }

  Future<String> _workersSubdomain() async {
    final result = _asMap(
      await _requestJson('GET', '/accounts/$accountId/workers/subdomain'),
    );
    final subdomain = '${result['subdomain'] ?? ''}'.trim();
    final enabled = result['enabled'] == true || subdomain.isNotEmpty;
    if (!enabled || subdomain.isEmpty) {
      throw const LocalRuntimeHelperException(
        'cloudflare_workers_subdomain_required',
        'Cloudflare workers.dev subdomain is not enabled for this account.',
      );
    }
    return subdomain;
  }

  Future<void> _uploadWorkerScript({
    required String workerName,
    required String d1DatabaseId,
    required String kvNamespaceId,
    required String r2BucketName,
    required SelfManagedSetupRequest request,
  }) async {
    final metadata = <String, Object?>{
      'main_module': 'main.mjs',
      'compatibility_date': '2026-05-26',
      'bindings': [
        <String, Object?>{
          'type': 'plain_text',
          'name': 'SECONDLOOP_RUNTIME_MODE',
          'text': 'self_managed',
        },
        <String, Object?>{
          'type': 'd1',
          'name': 'D1',
          'database_id': d1DatabaseId,
        },
        <String, Object?>{
          'type': 'kv_namespace',
          'name': 'KV',
          'namespace_id': kvNamespaceId,
        },
        <String, Object?>{
          'type': 'r2_bucket',
          'name': 'R2',
          'bucket_name': r2BucketName,
        },
        <String, Object?>{
          'type': 'plain_text',
          'name': 'SECRETARY_AGENT',
          'text': workerName,
        },
        if (request.apiKey.trim().isNotEmpty)
          <String, Object?>{
            'type': 'secret_text',
            'name': 'LLM_API_KEY',
            'text': request.apiKey.trim(),
          },
        if (request.embeddingApiKey.trim().isNotEmpty)
          <String, Object?>{
            'type': 'secret_text',
            'name': 'EMBEDDING_API_KEY',
            'text': request.embeddingApiKey.trim(),
          },
        if (request.multimodalApiKey.trim().isNotEmpty)
          <String, Object?>{
            'type': 'secret_text',
            'name': 'MULTIMODAL_LLM_API_KEY',
            'text': request.multimodalApiKey.trim(),
          },
      ],
    };
    await _uploadMultipartWorker(
      workerName,
      metadata: metadata,
      script: buildLocalQaWorkerScript(),
    );
    await _enableWorkerSubdomain(workerName);
  }

  Future<bool> _deleteWorkerScript(String workerName) async {
    try {
      await _requestJson(
        'DELETE',
        '/accounts/$accountId/workers/scripts/$workerName',
      );
      return true;
    } on LocalRuntimeHelperException catch (error) {
      if (error.code == 'cloudflare_api_not_found') return false;
      rethrow;
    }
  }

  Future<void> _enableWorkerSubdomain(String workerName) async {
    await _requestJson(
      'POST',
      '/accounts/$accountId/workers/scripts/$workerName/subdomain',
      body: <String, Object?>{'enabled': true},
    );
  }

  Future<void> _runHealthCheck(String apiBaseUrl) async {
    final uri = Uri.parse(apiBaseUrl).resolve('/health');
    final request = await _httpClient.getUrl(uri);
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalRuntimeHelperException(
        'runtime_health_check_failed',
        'Runtime health check failed with HTTP ${response.statusCode}: $raw',
      );
    }
  }

  Future<Object?> _requestJson(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse('https://api.cloudflare.com/client/v4$path');
    final request = await _httpClient.openUrl(method, uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiToken');
    request.headers.contentType = ContentType.json;
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    return _decodeCloudflareResponse(response.statusCode, raw);
  }

  Future<void> _uploadMultipartWorker(
    String workerName, {
    required Map<String, Object?> metadata,
    required String script,
  }) async {
    final boundary = 'secondloop-${DateTime.now().microsecondsSinceEpoch}';
    final body = _multipartBody(
      boundary: boundary,
      metadata: jsonEncode(metadata),
      script: script,
    );
    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$accountId/workers/scripts/$workerName',
    );
    final request = await _httpClient.putUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiToken');
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: <String, String>{'boundary': boundary},
    );
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    _decodeCloudflareResponse(response.statusCode, raw);
  }

  Object? _decodeCloudflareResponse(int statusCode, String raw) {
    final decoded = raw.trim().isEmpty ? <String, Object?>{} : jsonDecode(raw);
    if (decoded is! Map) {
      throw const LocalRuntimeHelperException(
        'cloudflare_api_invalid_response',
        'Cloudflare API response was not a JSON object.',
      );
    }
    final response = decoded.map((key, value) => MapEntry('$key', value));
    if (statusCode == 404) {
      throw LocalRuntimeHelperException(
        'cloudflare_api_not_found',
        _cloudflareErrorMessage(response, statusCode),
      );
    }
    if (statusCode < 200 || statusCode >= 300 || response['success'] == false) {
      throw LocalRuntimeHelperException(
        'cloudflare_api_error_$statusCode',
        _cloudflareErrorMessage(response, statusCode),
      );
    }
    return response['result'];
  }

  String _cloudflareErrorMessage(
      Map<String, Object?> response, int statusCode) {
    final errors = response['errors'];
    if (errors is List && errors.isNotEmpty) {
      return errors
          .map((error) {
            if (error is Map) {
              return '${error['code'] ?? ''} ${error['message'] ?? ''}'.trim();
            }
            return '$error';
          })
          .where((message) => message.trim().isNotEmpty)
          .join('; ');
    }
    return 'Cloudflare API request failed with HTTP $statusCode.';
  }
}

CloudflareRuntimeResourceNames buildCloudflareRuntimeResourceNames(
  Object request,
  SelfManagedRuntimeResourcePlan plan, {
  String? cloudflareAccountId,
}) {
  return _buildCloudflareRuntimeResourceNames(
    request,
    plan,
    cloudflareAccountId: cloudflareAccountId,
  );
}

CloudflareRuntimeResourceNames _buildCloudflareRuntimeResourceNames(
  Object request,
  SelfManagedRuntimeResourcePlan plan, {
  required String? cloudflareAccountId,
}) {
  final accountId = cloudflareAccountId ??
      switch (request) {
        SelfManagedSetupRequest() => request.cloudflareDeploymentAccountId,
        SelfManagedRuntimeUninstallRequest() =>
          request.cloudflareDeploymentAccountId,
        _ => '',
      };
  final runtimeId = switch (request) {
    SelfManagedRuntimeUninstallRequest() => request.runtimeId,
    _ => '',
  };
  final prefix = _resourcePrefix(accountId: accountId, runtimeId: runtimeId);
  final workerSuffixes = plan.workerNames.map(_slug).toList(growable: false);
  return CloudflareRuntimeResourceNames(
    prefix: prefix,
    workerNames: [
      for (final suffix in workerSuffixes)
        _trimCloudflareName('$prefix-$suffix', maxLength: 63),
    ],
    d1DatabaseName: _trimCloudflareName('$prefix-d1', maxLength: 64),
    kvNamespaceTitle: _trimCloudflareName('$prefix-kv', maxLength: 64),
    r2BucketName: _trimCloudflareName('$prefix-r2', maxLength: 63),
  );
}

List<int> _multipartBody({
  required String boundary,
  required String metadata,
  required String script,
}) {
  final bytes = <int>[];
  void write(String value) => bytes.addAll(utf8.encode(value));

  write('--$boundary\r\n');
  write('Content-Disposition: form-data; name="metadata"\r\n');
  write('Content-Type: application/json\r\n\r\n');
  write(metadata);
  write('\r\n--$boundary\r\n');
  write(
      'Content-Disposition: form-data; name="main.mjs"; filename="main.mjs"\r\n');
  write('Content-Type: application/javascript+module\r\n\r\n');
  write(script);
  write('\r\n--$boundary--\r\n');
  return bytes;
}

String? _stringField(Map<dynamic, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

List<Object?> _asList(Object? value) {
  if (value is List) return value;
  if (value is Map && value['items'] is List) return value['items'] as List;
  return const <Object?>[];
}

Map<dynamic, dynamic> _asMap(Object? value) {
  if (value is Map) return value;
  return const <dynamic, dynamic>{};
}

String _resourcePrefix({
  required String accountId,
  required String runtimeId,
}) {
  final explicit = _slug(runtimeId);
  if (explicit.isNotEmpty) {
    return _trimCloudflareName('secondloop-$explicit', maxLength: 40);
  }
  final accountPart = _slug(accountId).replaceAll('-', '');
  final short = accountPart.substring(0, min(accountPart.length, 12));
  return _trimCloudflareName(
    'secondloop-${short.isEmpty ? 'runtime' : short}',
    maxLength: 40,
  );
}

String _slug(String value) {
  final buffer = StringBuffer();
  var lastHyphen = false;
  for (final codeUnit in value.toLowerCase().codeUnits) {
    final char = String.fromCharCode(codeUnit);
    final keep = (codeUnit >= 97 && codeUnit <= 122) ||
        (codeUnit >= 48 && codeUnit <= 57);
    if (keep) {
      buffer.write(char);
      lastHyphen = false;
    } else if (!lastHyphen && buffer.isNotEmpty) {
      buffer.write('-');
      lastHyphen = true;
    }
  }
  return buffer.toString().replaceAll(RegExp('-+\$'), '');
}

String _trimCloudflareName(String value, {required int maxLength}) {
  var trimmed = _slug(value);
  if (trimmed.length > maxLength) {
    trimmed = trimmed.substring(0, maxLength);
  }
  return trimmed.replaceAll(RegExp('-+\$'), '');
}

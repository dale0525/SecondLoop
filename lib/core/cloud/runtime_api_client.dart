import 'dart:convert';

import 'package:http/http.dart' as http;

import 'runtime_connection_store.dart';
import 'runtime_profile.dart';

final class CloudRuntimeApiException implements Exception {
  const CloudRuntimeApiException({
    required this.uri,
    required this.statusCode,
    required this.responseBody,
  });

  final Uri uri;
  final int statusCode;
  final String responseBody;

  @override
  String toString() {
    return 'CloudRuntimeApiException(statusCode: $statusCode, uri: $uri, '
        'responseBody: $responseBody)';
  }
}

final class RuntimeApiClient {
  RuntimeApiClient({
    RuntimeConnectionStore? connectionStore,
    Future<CloudRuntimeConnection?> Function()? connectionLoader,
    http.Client? httpClient,
  })  : _connectionStore = connectionStore ?? RuntimeConnectionStore(),
        _connectionLoader = connectionLoader,
        _httpClient = httpClient ?? http.Client();

  final RuntimeConnectionStore _connectionStore;
  final Future<CloudRuntimeConnection?> Function()? _connectionLoader;
  final http.Client _httpClient;

  Future<Map<String, dynamic>?> getJson(
    String path, {
    Map<String, String>? headers,
  }) {
    return _sendJson(
      method: 'GET',
      path: path,
      headers: headers,
    );
  }

  Future<Map<String, dynamic>?> postJson(
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? headers,
  }) {
    return _sendJson(
      method: 'POST',
      path: path,
      body: body,
      headers: headers,
    );
  }

  Future<Map<String, dynamic>?> patchJson(
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? headers,
  }) {
    return _sendJson(
      method: 'PATCH',
      path: path,
      body: body,
      headers: headers,
    );
  }

  Future<Map<String, dynamic>?> _sendJson({
    required String method,
    required String path,
    Map<String, Object?>? body,
    Map<String, String>? headers,
  }) async {
    final connection =
        await (_connectionLoader ?? _connectionStore.loadConnection)();
    if (connection == null) {
      throw StateError('missing_cloud_runtime_connection');
    }

    final uri = Uri.parse(connection.manifest.apiBaseUrl).resolve(path);
    final request = http.Request(method, uri);
    request.headers.addAll(_buildHeaders(connection.profile));
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    final responseBody = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudRuntimeApiException(
        uri: uri,
        statusCode: response.statusCode,
        responseBody: responseBody,
      );
    }

    if (responseBody.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('invalid_cloud_runtime_response');
    }
    return decoded;
  }

  Map<String, String> _buildHeaders(CloudRuntimeProfile profile) {
    switch (profile.authMode) {
      case CloudRuntimeAuthMode.runtimeToken:
        return <String, String>{
          'accept': 'application/json',
          'authorization': 'Bearer ${profile.authToken}',
        };
      case CloudRuntimeAuthMode.hostedSession:
        return <String, String>{
          'accept': 'application/json',
          'authorization': 'Bearer ${profile.authToken}',
        };
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

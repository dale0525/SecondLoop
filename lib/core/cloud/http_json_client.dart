import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client_factory_stub.dart'
    if (dart.library.io) 'http_client_factory_io.dart';

class HttpJsonResponse {
  const HttpJsonResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  Map<String, dynamic>? tryDecodeObject() {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body) as Object?;
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

final class HttpJsonClient {
  HttpJsonClient({http.Client? client})
      : _client = client ?? createPlatformHttpClient();

  final http.Client _client;

  Future<HttpJsonResponse> get(
    Uri uri, {
    Map<String, String>? headers,
  }) =>
      _send(
        method: 'GET',
        uri: uri,
        headers: headers,
      );

  Future<HttpJsonResponse> delete(
    Uri uri, {
    Map<String, String>? headers,
  }) =>
      _send(
        method: 'DELETE',
        uri: uri,
        headers: headers,
      );

  Future<HttpJsonResponse> postJson(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _send(
        method: 'POST',
        uri: uri,
        headers: headers,
        body: body,
      );

  Future<HttpJsonResponse> putJson(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _send(
        method: 'PUT',
        uri: uri,
        headers: headers,
        body: body,
      );

  Future<HttpJsonResponse> _send({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final payload = body;

    final response = switch (method) {
      'GET' => await _client.get(uri, headers: headers),
      'DELETE' => await _client.delete(uri, headers: headers),
      'POST' => await _client.post(
          uri,
          headers: headers,
          body: payload == null ? null : jsonEncode(payload),
        ),
      'PUT' => await _client.put(
          uri,
          headers: headers,
          body: payload == null ? null : jsonEncode(payload),
        ),
      _ => throw UnsupportedError('unsupported_http_method:$method'),
    };
    return HttpJsonResponse(
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  void close() {
    _client.close();
  }
}

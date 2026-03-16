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
  HttpJsonClient({Object? client})
      : _client = client ?? createPlatformHttpClient();

  final Object _client;

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

  Future<HttpJsonResponse> _send({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final payload = body;

    if (_client is http.Client) {
      final client = _client;
      final response = switch (method) {
        'GET' => await client.get(uri, headers: headers),
        'DELETE' => await client.delete(uri, headers: headers),
        'POST' => await client.post(
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

    final legacyClient = _client as dynamic;
    final request = switch (method) {
      'GET' => await legacyClient.getUrl(uri),
      'DELETE' => await legacyClient.deleteUrl(uri),
      'POST' => await legacyClient.postUrl(uri),
      _ => throw UnsupportedError('unsupported_http_method:$method'),
    };

    final mergedHeaders = <String, String>{...?headers};
    if (method == 'POST' && payload != null) {
      mergedHeaders.putIfAbsent('content-type', () => 'application/json');
    }
    for (final entry in mergedHeaders.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (method == 'POST' && payload != null) {
      request.add(utf8.encode(jsonEncode(payload)));
    }

    final dynamic response = await request.close();
    final statusCode = response.statusCode as int;
    final responseBody = await utf8.decodeStream(response as Stream<List<int>>);
    return HttpJsonResponse(
      statusCode: statusCode,
      body: responseBody,
    );
  }

  void close() {
    if (_client is http.Client) {
      _client.close();
      return;
    }

    try {
      (_client as dynamic).close(force: true);
    } catch (_) {
      try {
        (_client as dynamic).close();
      } catch (_) {
        // ignore
      }
    }
  }
}

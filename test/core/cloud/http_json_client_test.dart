import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/http_json_client.dart';

void main() {
  test('HttpJsonClient decodes json object responses', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response('{"ok":true,"count":2}', 200);
    });

    final response = await HttpJsonClient(client: client).get(
      Uri.parse('https://gateway.test/v1/example'),
    );

    expect(response.tryDecodeObject(), <String, Object?>{
      'ok': true,
      'count': 2,
    });
  });

  test('HttpJsonClient returns null for empty successful responses', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response('', 200);
    });

    final response = await HttpJsonClient(client: client).get(
      Uri.parse('https://gateway.test/v1/example'),
    );

    expect(response.tryDecodeObject(), isNull);
  });
}

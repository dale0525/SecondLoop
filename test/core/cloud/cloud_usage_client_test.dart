import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';

void main() {
  test('CloudUsageClient parses ask ai and embeddings usage', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://gateway.test/v1/usage');
      expect(request.headers['authorization'], 'Bearer token-1');
      return http.Response(
        jsonEncode({
          'ask_ai_usage_percent': 42,
          'embeddings_usage_percent': 7,
          'reset_at_ms': 123456,
        }),
        200,
      );
    });

    final usageClient = CloudUsageClient(httpClient: client);
    final summary = await usageClient.fetchUsageSummary(
      cloudGatewayBaseUrl: 'https://gateway.test',
      idToken: 'token-1',
    );

    expect(summary.askAiUsagePercent, 42);
    expect(summary.embeddingsUsagePercent, 7);
    expect(summary.resetAtMs, 123456);
  });

  test('CloudUsageClient maps invalid json payload to domain format error',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response('not-json', 200);
    });

    final usageClient = CloudUsageClient(httpClient: client);

    await expectLater(
      () => usageClient.fetchUsageSummary(
        cloudGatewayBaseUrl: 'https://gateway.test',
        idToken: 'token-1',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'invalid_usage_response',
        ),
      ),
    );
  });

  test('CloudUsageClient maps empty successful payload to domain format error',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response('', 200);
    });

    final usageClient = CloudUsageClient(httpClient: client);

    await expectLater(
      () => usageClient.fetchUsageSummary(
        cloudGatewayBaseUrl: 'https://gateway.test',
        idToken: 'token-1',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'invalid_usage_response',
        ),
      ),
    );
  });
}

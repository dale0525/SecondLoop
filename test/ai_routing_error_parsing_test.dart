import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';

void main() {
  test('parseHttpStatusFromError parses alternative status formats', () {
    expect(parseHttpStatusFromError('StatusCode: 502'), 502);
    expect(parseHttpStatusFromError('status code=429'), 429);
    expect(parseHttpStatusFromError('status: 401'), 401);
  });

  test('parseCloudErrorCodeFromError parses nested error payloads', () {
    const message =
        'cloud-gateway request failed: HTTP 403 {"error":{"code":"email_not_verified"}}';
    expect(parseCloudErrorCodeFromError(message), 'email_not_verified');
  });

  test('isCloudFallbackableError includes 5xx errors', () {
    expect(
      isCloudFallbackableError(
        'cloud-gateway request failed: HTTP 502 {"error":"upstream_error"}',
      ),
      isTrue,
    );
  });
}

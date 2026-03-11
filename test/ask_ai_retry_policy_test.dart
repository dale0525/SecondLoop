import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';

void main() {
  test(
      'canRetryCloudAskWithoutEmbeddings is false when scoped stream is active',
      () {
    expect(
      canRetryCloudAskWithoutEmbeddings(
        route: AskAiRouteKind.cloudGateway,
        allowCloudEmbeddings: true,
        hasTimeWindow: false,
        hasScopedStream: true,
      ),
      isFalse,
    );
  });

  test('canRetryCloudAskWithoutEmbeddings is true for plain cloud asks', () {
    expect(
      canRetryCloudAskWithoutEmbeddings(
        route: AskAiRouteKind.cloudGateway,
        allowCloudEmbeddings: true,
        hasTimeWindow: false,
        hasScopedStream: false,
      ),
      isTrue,
    );
  });
}

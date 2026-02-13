import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/detached_ask_recovery_policy.dart';

void main() {
  test('poll delay is 3s for fresh detached jobs', () {
    expect(
      detachedAskRecoveryPollDelay(nowMs: 120000, createdAtMs: 119000),
      const Duration(seconds: 3),
    );
  });

  test('poll delay becomes 8s after 2 minutes', () {
    expect(
      detachedAskRecoveryPollDelay(nowMs: 120000, createdAtMs: 0),
      const Duration(seconds: 8),
    );
  });

  test('poll delay becomes 15s after 10 minutes', () {
    expect(
      detachedAskRecoveryPollDelay(nowMs: 610000, createdAtMs: 0),
      const Duration(seconds: 15),
    );
  });

  test('poll delay stays 3s when createdAt is missing', () {
    expect(
      detachedAskRecoveryPollDelay(nowMs: 999000, createdAtMs: null),
      const Duration(seconds: 3),
    );
  });

  test('poll delay clamps negative age to 3s', () {
    expect(
      detachedAskRecoveryPollDelay(nowMs: 100000, createdAtMs: 120000),
      const Duration(seconds: 3),
    );
  });
}

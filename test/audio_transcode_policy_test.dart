import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/features/media_backup/audio_transcode_policy.dart';

void main() {
  test('local audio transcode stays enabled for entitled subscription', () {
    final shouldUse = shouldUseLocalAudioTranscode(
      subscriptionStatus: SubscriptionStatus.entitled,
    );
    expect(shouldUse, isTrue);
  });

  test('local audio transcode stays enabled for not entitled subscription', () {
    final shouldUse = shouldUseLocalAudioTranscode(
      subscriptionStatus: SubscriptionStatus.notEntitled,
    );
    expect(shouldUse, isTrue);
  });

  test('local audio transcode stays enabled when subscription is unknown', () {
    final shouldUse = shouldUseLocalAudioTranscode(
      subscriptionStatus: SubscriptionStatus.unknown,
    );
    expect(shouldUse, isTrue);
  });
}

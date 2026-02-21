import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/features/media_backup/audio_transcode_policy.dart';

void main() {
  test('local audio transcode is disabled on Android', () {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previous;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final shouldUse = shouldUseLocalAudioTranscode(
      subscriptionStatus: SubscriptionStatus.entitled,
    );
    expect(shouldUse, isFalse);
  });

  test('local audio transcode is disabled on iOS', () {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previous;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final shouldUse = shouldUseLocalAudioTranscode(
      subscriptionStatus: SubscriptionStatus.notEntitled,
    );
    expect(shouldUse, isFalse);
  });

  test('local audio transcode stays enabled on desktop', () {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previous;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final shouldUse = shouldUseLocalAudioTranscode(
      subscriptionStatus: SubscriptionStatus.unknown,
    );
    expect(shouldUse, isTrue);
  });
}

import 'package:flutter/foundation.dart';

import '../../core/ai/ai_routing.dart';

bool shouldUseLocalAudioTranscode({
  required SubscriptionStatus subscriptionStatus,
}) {
  if (kIsWeb) return true;

  final platform = defaultTargetPlatform;
  final isMobile =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  if (isMobile) {
    return false;
  }

  // Keep local transcode enabled on desktop as best effort for cloud ingress.
  return true;
}

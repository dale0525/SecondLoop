import '../../core/ai/ai_routing.dart';

bool shouldUseLocalAudioTranscode({
  required SubscriptionStatus subscriptionStatus,
}) {
  // Audio proxy is required for Pro cloud ingress, so we keep local transcode
  // enabled for all tiers as best effort before upload.
  return true;
}

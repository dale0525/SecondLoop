import '../ai/ai_routing.dart';

class MediaEnrichmentAvailability {
  const MediaEnrichmentAvailability({
    required this.geoReverseAvailable,
    required this.annotationAvailable,
  });

  final bool geoReverseAvailable;
  final bool annotationAvailable;
}

MediaEnrichmentAvailability resolveMediaEnrichmentAvailability({
  required SubscriptionStatus subscriptionStatus,
  required String? cloudIdToken,
  required String gatewayBaseUrl,
}) {
  final hasAuth = cloudIdToken != null && cloudIdToken.trim().isNotEmpty;
  final hasGateway = gatewayBaseUrl.trim().isNotEmpty;
  final geoReverseAvailable =
      subscriptionStatus == SubscriptionStatus.entitled &&
          hasAuth &&
          hasGateway;

  // Geo reverse is now gated by subscription (server-side), so keep client-side
  // gating strict to avoid hammering the gateway with 402s.
  final annotationAvailable = geoReverseAvailable;

  return MediaEnrichmentAvailability(
    geoReverseAvailable: geoReverseAvailable,
    annotationAvailable: annotationAvailable,
  );
}

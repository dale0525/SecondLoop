import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/media_enrichment/media_enrichment_availability.dart';

void main() {
  test('Not entitled: geo reverse unavailable, annotation unavailable', () {
    final availability = resolveMediaEnrichmentAvailability(
      subscriptionStatus: SubscriptionStatus.notEntitled,
      cloudIdToken: 'token',
      gatewayBaseUrl: 'https://gateway.test',
    );
    expect(availability.geoReverseAvailable, isFalse);
    expect(availability.annotationAvailable, isFalse);
  });

  test('Entitled: geo reverse + annotation available', () {
    final availability = resolveMediaEnrichmentAvailability(
      subscriptionStatus: SubscriptionStatus.entitled,
      cloudIdToken: 'token',
      gatewayBaseUrl: 'https://gateway.test',
    );
    expect(availability.geoReverseAvailable, isTrue);
    expect(availability.annotationAvailable, isTrue);
  });

  test('Missing token/baseUrl: nothing available', () {
    final missingToken = resolveMediaEnrichmentAvailability(
      subscriptionStatus: SubscriptionStatus.entitled,
      cloudIdToken: '  ',
      gatewayBaseUrl: 'https://gateway.test',
    );
    expect(missingToken.geoReverseAvailable, isFalse);
    expect(missingToken.annotationAvailable, isFalse);

    final missingBaseUrl = resolveMediaEnrichmentAvailability(
      subscriptionStatus: SubscriptionStatus.entitled,
      cloudIdToken: 'token',
      gatewayBaseUrl: '  ',
    );
    expect(missingBaseUrl.geoReverseAvailable, isFalse);
    expect(missingBaseUrl.annotationAvailable, isFalse);
  });
}

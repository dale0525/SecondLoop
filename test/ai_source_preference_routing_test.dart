import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/embeddings_source_prefs.dart';
import 'package:secondloop/core/ai/media_source_prefs.dart';

void main() {
  group('resolveEmbeddingsSourceRoute', () {
    test('auto prefers cloud, then byok, then setup-required', () {
      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.auto,
          cloudEmbeddingsSelected: true,
          cloudAvailable: true,
          hasByokProfile: true,
        ),
        EmbeddingsSourceRouteKind.cloudGateway,
      );

      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.auto,
          cloudEmbeddingsSelected: false,
          cloudAvailable: true,
          hasByokProfile: true,
        ),
        EmbeddingsSourceRouteKind.byok,
      );

      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.auto,
          cloudEmbeddingsSelected: false,
          cloudAvailable: false,
          hasByokProfile: false,
        ),
        EmbeddingsSourceRouteKind.needsSetup,
      );
    });

    test('byok requires an embedding profile instead of local fallback', () {
      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.byok,
          cloudEmbeddingsSelected: true,
          cloudAvailable: true,
          hasByokProfile: false,
        ),
        EmbeddingsSourceRouteKind.needsSetup,
      );
    });

    test('byok does not fall back to cloud when profile is missing', () {
      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.byok,
          cloudEmbeddingsSelected: true,
          cloudAvailable: true,
          hasByokProfile: false,
          hasLocalCapability: false,
        ),
        EmbeddingsSourceRouteKind.needsSetup,
      );
    });

    test('cloud falls back to byok and then setup-required', () {
      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.cloud,
          cloudEmbeddingsSelected: true,
          cloudAvailable: false,
          hasByokProfile: true,
        ),
        EmbeddingsSourceRouteKind.byok,
      );

      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.cloud,
          cloudEmbeddingsSelected: true,
          cloudAvailable: false,
          hasByokProfile: false,
        ),
        EmbeddingsSourceRouteKind.needsSetup,
      );
    });

    test('legacy local preference no longer selects local embeddings', () {
      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.local,
          cloudEmbeddingsSelected: true,
          cloudAvailable: true,
          hasByokProfile: false,
        ),
        EmbeddingsSourceRouteKind.cloudGateway,
      );

      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.local,
          cloudEmbeddingsSelected: true,
          cloudAvailable: false,
          hasByokProfile: true,
        ),
        EmbeddingsSourceRouteKind.byok,
      );

      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.local,
          cloudEmbeddingsSelected: false,
          cloudAvailable: false,
          hasByokProfile: false,
        ),
        EmbeddingsSourceRouteKind.needsSetup,
      );
    });
  });

  group('resolveMediaSourceRoute', () {
    test('auto prefers cloud, then byok, then setup-required', () {
      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.auto,
          cloudAvailable: true,
          hasByokProfile: true,
        ),
        MediaSourceRouteKind.cloudGateway,
      );

      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.auto,
          cloudAvailable: false,
          hasByokProfile: true,
        ),
        MediaSourceRouteKind.byok,
      );

      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.auto,
          cloudAvailable: false,
          hasByokProfile: false,
        ),
        MediaSourceRouteKind.needsSetup,
      );
    });

    test('byok requires a multimodal profile instead of local fallback', () {
      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.byok,
          cloudAvailable: true,
          hasByokProfile: false,
        ),
        MediaSourceRouteKind.needsSetup,
      );
    });

    test('byok does not fall back to cloud when profile is missing', () {
      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.byok,
          cloudAvailable: true,
          hasByokProfile: false,
          hasLocalCapability: false,
        ),
        MediaSourceRouteKind.needsSetup,
      );
    });

    test('cloud falls back to byok and then setup-required', () {
      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.cloud,
          cloudAvailable: false,
          hasByokProfile: true,
        ),
        MediaSourceRouteKind.byok,
      );

      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.cloud,
          cloudAvailable: false,
          hasByokProfile: false,
        ),
        MediaSourceRouteKind.needsSetup,
      );
    });

    test('legacy local preference no longer selects local media capability',
        () {
      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.local,
          cloudAvailable: true,
          hasByokProfile: false,
        ),
        MediaSourceRouteKind.cloudGateway,
      );

      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.local,
          cloudAvailable: false,
          hasByokProfile: true,
        ),
        MediaSourceRouteKind.byok,
      );

      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.local,
          cloudAvailable: false,
          hasByokProfile: false,
        ),
        MediaSourceRouteKind.needsSetup,
      );
    });
  });
}

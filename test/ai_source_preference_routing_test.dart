import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/embeddings_source_prefs.dart';
import 'package:secondloop/core/ai/media_source_prefs.dart';

void main() {
  group('resolveEmbeddingsSourceRoute', () {
    test('auto prefers cloud, then byok, then local', () {
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
        EmbeddingsSourceRouteKind.local,
      );
    });

    test('byok falls back to local when profile is unavailable', () {
      expect(
        resolveEmbeddingsSourceRoute(
          EmbeddingsSourcePreference.byok,
          cloudEmbeddingsSelected: true,
          cloudAvailable: true,
          hasByokProfile: false,
        ),
        EmbeddingsSourceRouteKind.local,
      );
    });

    test('cloud falls back to byok/local when cloud is unavailable', () {
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
        EmbeddingsSourceRouteKind.local,
      );
    });
  });

  group('resolveMediaSourceRoute', () {
    test('auto prefers cloud, then byok, then local', () {
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
        MediaSourceRouteKind.local,
      );
    });

    test('byok falls back to local when profile is unavailable', () {
      expect(
        resolveMediaSourceRoute(
          MediaSourcePreference.byok,
          cloudAvailable: true,
          hasByokProfile: false,
        ),
        MediaSourceRouteKind.local,
      );
    });

    test('cloud falls back to byok/local when cloud is unavailable', () {
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
        MediaSourceRouteKind.local,
      );
    });
  });
}

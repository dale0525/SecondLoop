part of 'media_enrichment_gate.dart';

@visibleForTesting
UrlEnrichmentEnhancerResult? parseUrlEnrichmentPayloadForTest(String raw) {
  return _RuntimeUrlEnrichmentEnhancer.parsePayload(raw);
}

extension _MediaEnrichmentGateUrlEnrichmentExtension
    on _MediaEnrichmentGateState {
  List<UrlEnrichmentEnhancer> _buildUrlEnrichmentEnhancers({
    required MediaSourcePreference preference,
    required bool cloudAvailable,
    required LlmProfile? byokProfile,
    required String gatewayBaseUrl,
    required String cloudIdToken,
    required String cloudModelName,
  }) {
    final enrichers = <UrlEnrichmentEnhancer>[];
    final orderedRoutes = mediaSourceFallbackOrder(preference);
    final normalizedGatewayBaseUrl = gatewayBaseUrl.trim();
    final normalizedCloudIdToken = cloudIdToken.trim();
    final normalizedCloudModelName = cloudModelName.trim();

    for (final route in orderedRoutes) {
      switch (route) {
        case MediaSourceRouteKind.cloudGateway:
          if (!cloudAvailable) continue;
          if (normalizedGatewayBaseUrl.isEmpty ||
              normalizedCloudIdToken.isEmpty ||
              normalizedCloudModelName.isEmpty) {
            continue;
          }
          enrichers.add(
            _RuntimeUrlEnrichmentEnhancer.cloud(
              modelName: normalizedCloudModelName,
            ),
          );
          break;
        case MediaSourceRouteKind.byok:
          if (byokProfile == null) continue;
          enrichers.add(
            _RuntimeUrlEnrichmentEnhancer.byok(
              modelName: byokProfile.modelName,
            ),
          );
          break;
        case MediaSourceRouteKind.needsSetup:
          break;
        case MediaSourceRouteKind.local:
          break;
      }
    }

    return enrichers;
  }
}

enum _RuntimeUrlEnrichmentRouteKind {
  cloud,
  byok,
}

final class _RuntimeUrlEnrichmentEnhancer implements UrlEnrichmentEnhancer {
  _RuntimeUrlEnrichmentEnhancer._({
    required this.route,
    required this.modelName,
  });

  factory _RuntimeUrlEnrichmentEnhancer.cloud({
    required String modelName,
  }) {
    return _RuntimeUrlEnrichmentEnhancer._(
      route: _RuntimeUrlEnrichmentRouteKind.cloud,
      modelName: modelName,
    );
  }

  factory _RuntimeUrlEnrichmentEnhancer.byok({
    required String modelName,
  }) {
    return _RuntimeUrlEnrichmentEnhancer._(
      route: _RuntimeUrlEnrichmentRouteKind.byok,
      modelName: modelName,
    );
  }

  final _RuntimeUrlEnrichmentRouteKind route;

  @override
  final String modelName;

  @override
  String get source => switch (route) {
        _RuntimeUrlEnrichmentRouteKind.cloud => 'cloud',
        _RuntimeUrlEnrichmentRouteKind.byok => 'byok',
      };

  @override
  Future<UrlEnrichmentEnhancerResult?> enhance({
    required String lang,
    required String originalUrl,
    required String finalUrl,
    required String site,
    required String? title,
    required String readableTextExcerpt,
    required String readableTextFull,
  }) async {
    return null;
  }

  static UrlEnrichmentEnhancerResult? parsePayload(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final map = Map<String, Object?>.from(decoded);
    final title = _readString(map, 'title');
    final summary = _readString(map, 'summary');
    final tags = _readTags(map['tags']);
    if ((title ?? '').isEmpty && (summary ?? '').isEmpty && tags.isEmpty) {
      return null;
    }

    return UrlEnrichmentEnhancerResult(
      title: title,
      summary: summary,
      tags: tags,
    );
  }

  static String? _readString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static List<String> _readTags(Object? raw) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) continue;
      final normalized = item.trim();
      if (normalized.isEmpty) continue;
      final dedupKey = normalized.toLowerCase();
      if (!seen.add(dedupKey)) continue;
      out.add(normalized);
      if (out.length >= 6) break;
    }
    return out;
  }
}

part of 'media_enrichment_gate.dart';

@visibleForTesting
UrlEnrichmentEnhancerResult? parseUrlEnrichmentPayloadForTest(String raw) {
  return _RustUrlEnrichmentEnhancer.parsePayload(raw);
}

extension _MediaEnrichmentGateUrlEnrichmentExtension
    on _MediaEnrichmentGateState {
  List<UrlEnrichmentEnhancer> _buildUrlEnrichmentEnhancers({
    required MediaSourcePreference preference,
    required bool cloudAvailable,
    required LlmProfile? byokProfile,
    required Uint8List sessionKey,
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
            _RustUrlEnrichmentEnhancer.cloud(
              sessionKey: sessionKey,
              gatewayBaseUrl: normalizedGatewayBaseUrl,
              cloudIdToken: normalizedCloudIdToken,
              modelName: normalizedCloudModelName,
            ),
          );
          break;
        case MediaSourceRouteKind.byok:
          if (byokProfile == null) continue;
          enrichers.add(
            _RustUrlEnrichmentEnhancer.byok(
              sessionKey: sessionKey,
              profileId: byokProfile.id,
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

enum _RustUrlEnrichmentRouteKind {
  cloud,
  byok,
}

final class _RustUrlEnrichmentEnhancer implements UrlEnrichmentEnhancer {
  _RustUrlEnrichmentEnhancer._({
    required Uint8List sessionKey,
    required this.route,
    required this.modelName,
    this.profileId,
    this.gatewayBaseUrl,
    this.cloudIdToken,
  }) : _sessionKey = Uint8List.fromList(sessionKey);

  factory _RustUrlEnrichmentEnhancer.cloud({
    required Uint8List sessionKey,
    required String gatewayBaseUrl,
    required String cloudIdToken,
    required String modelName,
  }) {
    return _RustUrlEnrichmentEnhancer._(
      sessionKey: sessionKey,
      route: _RustUrlEnrichmentRouteKind.cloud,
      modelName: modelName,
      gatewayBaseUrl: gatewayBaseUrl,
      cloudIdToken: cloudIdToken,
    );
  }

  factory _RustUrlEnrichmentEnhancer.byok({
    required Uint8List sessionKey,
    required String profileId,
    required String modelName,
  }) {
    return _RustUrlEnrichmentEnhancer._(
      sessionKey: sessionKey,
      route: _RustUrlEnrichmentRouteKind.byok,
      modelName: modelName,
      profileId: profileId,
    );
  }

  final Uint8List _sessionKey;
  final _RustUrlEnrichmentRouteKind route;
  final String? profileId;
  final String? gatewayBaseUrl;
  final String? cloudIdToken;

  @override
  final String modelName;

  @override
  String get source => switch (route) {
        _RustUrlEnrichmentRouteKind.cloud => 'cloud',
        _RustUrlEnrichmentRouteKind.byok => 'byok',
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
    final appDir = await getNativeAppDir();
    final normalizedTitle = _normalizeOptionalTitle(title);
    final payloadJson = switch (route) {
      _RustUrlEnrichmentRouteKind.cloud =>
        await rust_media_annotation.urlEnrichmentCloudGateway(
          appDir: appDir,
          key: _sessionKey,
          gatewayBaseUrl: gatewayBaseUrl ?? '',
          firebaseIdToken: cloudIdToken ?? '',
          modelName: modelName,
          lang: lang,
          originalUrl: originalUrl,
          finalUrl: finalUrl,
          site: site,
          title: normalizedTitle,
          readableTextExcerpt: readableTextExcerpt,
          readableTextFull: readableTextFull,
        ),
      _RustUrlEnrichmentRouteKind.byok =>
        await rust_media_annotation.urlEnrichmentByokProfile(
          appDir: appDir,
          key: _sessionKey,
          profileId: profileId ?? '',
          lang: lang,
          originalUrl: originalUrl,
          finalUrl: finalUrl,
          site: site,
          title: normalizedTitle,
          readableTextExcerpt: readableTextExcerpt,
          readableTextFull: readableTextFull,
        ),
    };

    return parsePayload(payloadJson);
  }

  static String? _normalizeOptionalTitle(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed;
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

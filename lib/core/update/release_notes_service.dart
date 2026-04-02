import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app_update_helpers.dart';
import 'app_update_models.dart';
import 'app_update_resolution.dart';
import 'release_endpoint_helpers.dart';

const _defaultReleaseApiOrigin = String.fromEnvironment(
  'SECONDLOOP_RELEASE_API_ORIGIN',
  defaultValue: 'https://secondloop.app',
);
const _defaultReleaseRepo = String.fromEnvironment(
  'SECONDLOOP_RELEASE_REPO',
  defaultValue: 'dale0525/SecondLoop',
);
const _defaultReleaseNotesNetworkTimeout = Duration(seconds: 15);

class ReleaseNotesSection {
  const ReleaseNotesSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;
}

class ReleaseNotes {
  const ReleaseNotes({
    required this.version,
    required this.summary,
    required this.highlights,
    required this.sections,
  });

  final String version;
  final String summary;
  final List<String> highlights;
  final List<ReleaseNotesSection> sections;
}

class ReleaseNotesFetchResult {
  const ReleaseNotesFetchResult({
    this.notes,
    this.sourceLocaleTag,
    this.releasePageUri,
    this.errorMessage,
  });

  final ReleaseNotes? notes;
  final String? sourceLocaleTag;
  final Uri? releasePageUri;
  final String? errorMessage;
}

typedef ReleaseNotesReleaseJsonFetcher = Future<Map<String, Object?>> Function(
  Uri uri,
);
typedef ReleaseNotesJsonFetcher = Future<Map<String, Object?>> Function(
  Uri uri,
);

class ReleaseNotesService {
  ReleaseNotesService({
    HttpClient? httpClient,
    ReleaseNotesReleaseJsonFetcher? releaseJsonFetcher,
    ReleaseNotesJsonFetcher? notesJsonFetcher,
    String? releaseApiOriginOverride,
    String? releaseRepoOverride,
    Duration? networkTimeoutOverride,
    bool? allowHttpUriOverride,
    bool? allowFileUriOverride,
  })  : _httpClient = httpClient ?? HttpClient(),
        _releaseJsonFetcher = releaseJsonFetcher,
        _notesJsonFetcher = notesJsonFetcher,
        _releaseApiOriginOverride = releaseApiOriginOverride,
        _releaseRepoOverride = releaseRepoOverride,
        _networkTimeoutOverride = networkTimeoutOverride,
        _allowHttpUriOverride = allowHttpUriOverride,
        _allowFileUriOverride = allowFileUriOverride;

  final HttpClient _httpClient;
  final ReleaseNotesReleaseJsonFetcher? _releaseJsonFetcher;
  final ReleaseNotesJsonFetcher? _notesJsonFetcher;
  final String? _releaseApiOriginOverride;
  final String? _releaseRepoOverride;
  final Duration? _networkTimeoutOverride;
  final bool? _allowHttpUriOverride;
  final bool? _allowFileUriOverride;

  Duration get _networkTimeout =>
      _networkTimeoutOverride ?? _defaultReleaseNotesNetworkTimeout;
  bool get _allowHttpUris => _allowHttpUriOverride ?? false;
  bool get _allowFileUris => _allowFileUriOverride ?? false;

  Future<ReleaseNotesFetchResult> fetchReleaseNotes({
    required String tag,
    required Locale locale,
  }) async {
    final normalizedTag = _normalizeTag(tag);
    if (normalizedTag == null) {
      return const ReleaseNotesFetchResult(errorMessage: 'invalid_tag');
    }

    Map<String, Object?>? release;
    Object? lastError;
    for (final endpoint in _buildReleaseEndpoints(tag: normalizedTag)) {
      try {
        final next = await _fetchReleaseJson(endpoint);
        final releaseTag = _readString(next, 'tag_name');
        if (releaseTag == null || _normalizeTag(releaseTag) != normalizedTag) {
          continue;
        }
        release = next;
        break;
      } catch (error) {
        lastError = error;
      }
    }

    if (release == null) {
      return ReleaseNotesFetchResult(
        errorMessage: lastError?.toString() ?? 'missing_release',
      );
    }

    final releasePageUri = _parseUri(_readString(release, 'html_url'));
    final noteAsset = _matchReleaseNotesAsset(
      assets: _parseAssets(release['assets'], expectedTag: normalizedTag),
      tag: normalizedTag,
      locale: locale,
    );
    if (noteAsset == null) {
      return ReleaseNotesFetchResult(
        releasePageUri: releasePageUri,
        errorMessage: 'missing_release_notes_asset',
      );
    }

    try {
      final notesPayload = await _fetchNotesJson(noteAsset.downloadUri);
      final notes = _parseReleaseNotes(notesPayload);
      if (notes == null) {
        return ReleaseNotesFetchResult(
          releasePageUri: releasePageUri,
          errorMessage: 'invalid_release_notes_payload',
        );
      }
      return ReleaseNotesFetchResult(
        notes: notes,
        sourceLocaleTag: noteAsset.localeTag,
        releasePageUri: releasePageUri,
      );
    } catch (error) {
      return ReleaseNotesFetchResult(
        releasePageUri: releasePageUri,
        errorMessage: error.toString(),
      );
    }
  }

  void dispose() {
    _httpClient.close(force: true);
  }

  List<Uri> _buildReleaseEndpoints({required String tag}) {
    final endpoints = <Uri>[];

    final apiOrigin = _parseUri(
      (_releaseApiOriginOverride ?? _defaultReleaseApiOrigin).trim(),
    );
    if (apiOrigin != null) {
      endpoints.add(buildLatestReleaseEndpoint(apiOrigin));
    }

    final repo = (_releaseRepoOverride ?? _defaultReleaseRepo).trim();
    if (repo.isNotEmpty) {
      endpoints
          .add(Uri.https('api.github.com', '/repos/$repo/releases/tags/$tag'));
    }

    return endpoints;
  }

  Future<Map<String, Object?>> _fetchReleaseJson(Uri uri) async {
    final fetcher = _releaseJsonFetcher;
    if (fetcher != null) {
      return fetcher(uri).timeout(_networkTimeout);
    }

    final req = await _httpClient.getUrl(uri).timeout(_networkTimeout);
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final resp = await req.close().timeout(_networkTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('http_${resp.statusCode}', uri: uri);
    }

    return _decodeJsonMap(
      await utf8.decoder.bind(resp.timeout(_networkTimeout)).join(),
    );
  }

  Future<Map<String, Object?>> _fetchNotesJson(Uri uri) async {
    final fetcher = _notesJsonFetcher;
    if (fetcher != null) {
      return fetcher(uri).timeout(_networkTimeout);
    }

    final req = await _httpClient.getUrl(uri).timeout(_networkTimeout);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final resp = await req.close().timeout(_networkTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('http_${resp.statusCode}', uri: uri);
    }

    return _decodeJsonMap(
      await utf8.decoder.bind(resp.timeout(_networkTimeout)).join(),
    );
  }

  Map<String, Object?> _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('invalid_json_map');
    }

    final mapped = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) continue;
      mapped[entry.key as String] = entry.value;
    }
    return mapped;
  }

  ReleaseNotes? _parseReleaseNotes(Map<String, Object?> payload) {
    final summary = _readString(payload, 'summary') ?? '';
    final version = _readString(payload, 'version') ?? '';

    final highlights = <String>[];
    final rawHighlights = payload['highlights'];
    if (rawHighlights is List) {
      for (final item in rawHighlights) {
        if (item is! Map) continue;
        final text = item['text'];
        if (text is String && text.trim().isNotEmpty) {
          highlights.add(text.trim());
        }
      }
    }

    final sections = <ReleaseNotesSection>[];
    final rawSections = payload['sections'];
    if (rawSections is List) {
      for (final section in rawSections) {
        if (section is! Map) continue;
        final title = section['title'];
        final rawItems = section['items'];
        if (title is! String || rawItems is! List) continue;

        final items = <String>[];
        for (final rawItem in rawItems) {
          if (rawItem is! Map) continue;
          final text = rawItem['text'];
          if (text is String && text.trim().isNotEmpty) {
            items.add(text.trim());
          }
        }
        if (items.isEmpty) continue;

        sections.add(
          ReleaseNotesSection(
            title: title.trim().isEmpty ? 'Updates' : title.trim(),
            items: items,
          ),
        );
      }
    }

    if (summary.isEmpty && sections.isEmpty && highlights.isEmpty) {
      return null;
    }

    return ReleaseNotes(
      version: version,
      summary: summary,
      highlights: highlights,
      sections: sections,
    );
  }

  _ReleaseNotesAsset? _matchReleaseNotesAsset({
    required List<_ReleaseNotesAsset> assets,
    required String tag,
    required Locale locale,
  }) {
    final releaseAssets = <_ReleaseNotesAsset>[];
    for (final asset in assets) {
      if (asset.tag == tag) {
        releaseAssets.add(asset);
      }
    }
    if (releaseAssets.isEmpty) return null;

    final candidates = _localeCandidates(locale);
    for (final candidate in candidates) {
      for (final asset in releaseAssets) {
        if (_normalizeLocaleTag(asset.localeTag) == candidate) {
          return asset;
        }
      }
    }

    for (final asset in releaseAssets) {
      final normalized = _normalizeLocaleTag(asset.localeTag);
      if (normalized == 'en-us' || normalized == 'en') {
        return asset;
      }
    }

    return releaseAssets.first;
  }

  List<_ReleaseNotesAsset> _parseAssets(
    Object? rawAssets, {
    String? expectedTag,
  }) {
    if (rawAssets is! List) return const [];

    final parsed = <_ReleaseNotesAsset>[];
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final name = item['name'];
      final url = item['browser_download_url'];
      if (name is! String || url is! String) continue;

      final uri = _parseUri(url.trim());
      if (uri == null) continue;

      final parsedName = _parseReleaseNotesAssetFileName(
        name.trim(),
        expectedTag: expectedTag,
      );
      if (parsedName == null) continue;

      final tag = _normalizeTag(parsedName.$1);
      final localeTag = parsedName.$2;
      if (tag == null) continue;

      parsed.add(
        _ReleaseNotesAsset(
          tag: tag,
          localeTag: localeTag,
          downloadUri: uri,
        ),
      );
    }

    return parsed;
  }

  Uri? _parseUri(String? value) {
    return parseUpdateUri(
      value,
      allowHttp: _allowHttpUris,
      allowFile: _allowFileUris,
    );
  }

  static String? _readString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }
}

(String, String)? _parseReleaseNotesAssetFileName(
  String value, {
  String? expectedTag,
}) {
  const prefix = 'release-notes-';
  const suffix = '.json';
  final trimmed = value.trim();
  if (!trimmed.toLowerCase().startsWith(prefix) ||
      !trimmed.toLowerCase().endsWith(suffix)) {
    return null;
  }

  final body = trimmed.substring(prefix.length, trimmed.length - suffix.length);
  final normalizedExpectedTag = _normalizeTag(expectedTag);
  if (normalizedExpectedTag != null) {
    if (_normalizeTag(body) == normalizedExpectedTag) {
      return (body, 'en-US');
    }

    final expectedPrefix = '$normalizedExpectedTag-';
    if (body.length > expectedPrefix.length &&
        body.toLowerCase().startsWith(expectedPrefix.toLowerCase())) {
      final locale = body.substring(normalizedExpectedTag.length + 1).trim();
      if (_isLikelyLocaleTag(locale)) {
        return (normalizedExpectedTag, locale);
      }
    }
  }

  for (var index = body.indexOf('-');
      index >= 0;
      index = body.indexOf('-', index + 1)) {
    final candidateTag = body.substring(0, index).trim();
    final candidateLocale = body.substring(index + 1).trim();
    if (_normalizeTag(candidateTag) == null ||
        !_isLikelyLocaleTag(candidateLocale)) {
      continue;
    }
    return (candidateTag, candidateLocale);
  }

  if (_normalizeTag(body) != null) {
    return (body, 'en-US');
  }

  return null;
}

bool _isLikelyLocaleTag(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(r'^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]+)+$').hasMatch(normalized) ||
      RegExp(r'^[A-Za-z]{2,3}$').hasMatch(normalized);
}

class _ReleaseNotesAsset {
  const _ReleaseNotesAsset({
    required this.tag,
    required this.localeTag,
    required this.downloadUri,
  });

  final String tag;
  final String localeTag;
  final Uri downloadUri;
}

String? _normalizeTag(String? value) {
  final normalized = normalizeLatestTag(value);
  if (normalized == null) {
    return null;
  }
  if (parseComparableAppVersion(normalized) == null) {
    return null;
  }
  return normalized;
}

String? normalizeReleaseTag(String? value) => _normalizeTag(value);

String _normalizeLocaleTag(String value) {
  return value.trim().replaceAll('_', '-').toLowerCase();
}

List<String> _localeCandidates(Locale locale) {
  final languageCode = locale.languageCode.trim();
  final scriptCode = (locale.scriptCode ?? '').trim();
  final countryCode = (locale.countryCode ?? '').trim();

  final candidates = <String>[];
  void addCandidate(String value) {
    final normalized = _normalizeLocaleTag(value);
    if (normalized.isEmpty || candidates.contains(normalized)) return;
    candidates.add(normalized);
  }

  if (languageCode.isNotEmpty &&
      scriptCode.isNotEmpty &&
      countryCode.isNotEmpty) {
    addCandidate('$languageCode-$scriptCode-$countryCode');
    addCandidate('${languageCode}_${scriptCode}_$countryCode');
  }
  if (languageCode.isNotEmpty && scriptCode.isNotEmpty) {
    addCandidate('$languageCode-$scriptCode');
    addCandidate('${languageCode}_$scriptCode');
  }
  if (languageCode.isNotEmpty && countryCode.isNotEmpty) {
    addCandidate('$languageCode-$countryCode');
    addCandidate('${languageCode}_$countryCode');
  }
  if (languageCode.isNotEmpty) {
    addCandidate(languageCode);
  }

  return candidates;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String kSecondLoopUrlManifestMimeType =
    'application/x.secondloop.url+json';
const String kSecondLoopUrlManifestSchema = 'secondloop.url_manifest.v1';
const String kSecondLoopUrlEnrichmentSchema = 'secondloop.url_enrichment.v1';

const String kUrlEnrichmentModelName = 'url_enrichment.v1';

const int kUrlEnrichmentMaxFullTextBytes = 256 * 1024;
const int kUrlEnrichmentMaxExcerptBytes = 8 * 1024;

class UrlEnrichmentJob {
  const UrlEnrichmentJob({
    required this.attachmentSha256,
    required this.lang,
    required this.status,
    required this.attempts,
    required this.nextRetryAtMs,
  });

  final String attachmentSha256;
  final String lang;
  final String status;
  final int attempts;
  final int? nextRetryAtMs;
}

abstract class UrlEnrichmentStore {
  Future<List<UrlEnrichmentJob>> listDueUrlAnnotations({
    required int nowMs,
    int limit = 5,
  });

  Future<Uint8List> readAttachmentBytes({required String attachmentSha256});

  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  });

  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  });

  Future<void> upsertAttachmentTitle({
    required String attachmentSha256,
    required String title,
  });
}

class UrlFetchResponse {
  const UrlFetchResponse({
    required this.finalUri,
    required this.statusCode,
    required this.contentType,
    required this.bodyBytes,
  });

  final Uri finalUri;
  final int statusCode;
  final String? contentType;
  final Uint8List bodyBytes;
}

abstract class UrlEnrichmentFetcher {
  Future<UrlFetchResponse> fetch(Uri uri);
}

class UrlEnrichmentSecurityPolicy {
  UrlEnrichmentSecurityPolicy({
    this.allowLocalhost = false,
    this.allowPrivateIps = false,
    Future<List<InternetAddress>> Function(String host)? resolveHost,
  }) : _resolveHost = resolveHost ?? InternetAddress.lookup;

  final bool allowLocalhost;
  final bool allowPrivateIps;
  final Future<List<InternetAddress>> Function(String host) _resolveHost;

  Future<void> validate(Uri uri) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw StateError('url_scheme_not_allowed');
    }
    if (uri.userInfo.isNotEmpty) {
      throw StateError('url_userinfo_not_allowed');
    }

    final host = uri.host.trim();
    if (host.isEmpty) {
      throw StateError('url_host_required');
    }

    final lower = host.toLowerCase();
    if (!allowLocalhost) {
      if (lower == 'localhost' || lower.endsWith('.localhost')) {
        throw StateError('url_localhost_blocked');
      }
      if (lower.endsWith('.local')) {
        throw StateError('url_local_domain_blocked');
      }
    }

    if (allowPrivateIps) return;

    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      if (_isPrivateOrLocalAddress(literal)) {
        throw StateError('url_private_address_blocked');
      }
      return;
    }

    final addrs = await _resolveHost(host);
    for (final addr in addrs) {
      if (_isPrivateOrLocalAddress(addr)) {
        throw StateError('url_private_address_blocked');
      }
    }
  }

  bool _isPrivateOrLocalAddress(InternetAddress addr) {
    if (allowLocalhost) return false;

    if (addr.isLoopback) return true;
    if (addr.isLinkLocal) return true;

    final raw = addr.rawAddress;
    if (addr.type == InternetAddressType.IPv4 && raw.length == 4) {
      final a = raw[0];
      final b = raw[1];
      if (a == 10) return true;
      if (a == 127) return true;
      if (a == 0) return true;
      if (a == 169 && b == 254) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 192 && b == 168) return true;
      if (a == 100 && b >= 64 && b <= 127) return true;
      return false;
    }

    if (addr.type == InternetAddressType.IPv6 && raw.length == 16) {
      final isUnspecified = raw.every((b) => b == 0);
      if (isUnspecified) return true;
      // fc00::/7 unique local addresses
      if ((raw[0] & 0xFE) == 0xFC) return true;
      // fe80::/10 link-local
      if (raw[0] == 0xFE && (raw[1] & 0xC0) == 0x80) return true;
      return false;
    }

    return false;
  }
}

class HttpUrlEnrichmentFetcher implements UrlEnrichmentFetcher {
  HttpUrlEnrichmentFetcher({
    required this.securityPolicy,
    this.maxRedirects = 4,
    this.maxResponseBytes = 5 * 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 12),
    this.userAgent = 'SecondLoop/1.0 (url_enrichment_v1)',
  });

  final UrlEnrichmentSecurityPolicy securityPolicy;
  final int maxRedirects;
  final int maxResponseBytes;
  final Duration requestTimeout;
  final String userAgent;

  @override
  Future<UrlFetchResponse> fetch(Uri uri) async {
    Uri current = uri;
    for (var i = 0; i <= maxRedirects; i++) {
      await securityPolicy.validate(current);

      final client = HttpClient()
        ..autoUncompress = true
        ..connectionTimeout = requestTimeout
        ..userAgent = userAgent;

      try {
        final req = await client.getUrl(current).timeout(requestTimeout);
        req.followRedirects = false;
        req.headers.set(
          HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        );

        final resp = await req.close().timeout(requestTimeout);
        final status = resp.statusCode;
        final location = resp.headers.value(HttpHeaders.locationHeader);

        if (status >= 300 && status < 400 && location != null) {
          current = current.resolve(location.trim());
          continue;
        }

        if (status < 200 || status >= 300) {
          throw StateError('http_status_$status');
        }

        final body = await _readToBytesWithLimit(resp, maxResponseBytes);
        return UrlFetchResponse(
          finalUri: current,
          statusCode: status,
          contentType: resp.headers.contentType?.mimeType,
          bodyBytes: body,
        );
      } finally {
        client.close(force: true);
      }
    }

    throw StateError('too_many_redirects');
  }

  static Future<Uint8List> _readToBytesWithLimit(
    HttpClientResponse resp,
    int maxBytes,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in resp) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw StateError('response_too_large');
      }
    }
    return builder.takeBytes();
  }
}

class UrlEnrichmentRunResult {
  const UrlEnrichmentRunResult({required this.processed});

  final int processed;
  bool get didEnrichAny => processed > 0;
}

class UrlEnrichmentRunner {
  UrlEnrichmentRunner({
    required this.store,
    required this.fetcher,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final UrlEnrichmentStore store;
  final UrlEnrichmentFetcher fetcher;
  final int Function() _nowMs;

  Future<UrlEnrichmentRunResult> runOnce({int limit = 5}) async {
    final nowMs = _nowMs();
    final due = await store.listDueUrlAnnotations(nowMs: nowMs, limit: limit);
    if (due.isEmpty) return const UrlEnrichmentRunResult(processed: 0);

    var processed = 0;
    for (final job in due) {
      if (job.status == 'ok') continue;
      try {
        final manifestBytes = await store.readAttachmentBytes(
          attachmentSha256: job.attachmentSha256,
        );
        final manifest = _parseUrlManifest(manifestBytes);
        final url = _parseHttpUrl(manifest.url);

        final fetched = await fetcher.fetch(url);
        final html = _decodeBestEffortUtf8(fetched.bodyBytes);
        final extracted = _extractFromHtml(html, baseUri: fetched.finalUri);

        final fullText = _truncateUtf8ToMaxBytes(
          extracted.readableText,
          kUrlEnrichmentMaxFullTextBytes,
        );
        final excerpt = _truncateUtf8ToMaxBytes(
          fullText,
          kUrlEnrichmentMaxExcerptBytes,
        );

        final payload = jsonEncode({
          'schema': kSecondLoopUrlEnrichmentSchema,
          'url': manifest.url,
          'final_url': fetched.finalUri.toString(),
          'canonical_url': extracted.canonicalUrl,
          'site': extracted.site,
          'title': extracted.title,
          'readable_text_full': fullText,
          'readable_text_excerpt': excerpt,
          'fetched_at_ms': nowMs,
        });

        await store.markAnnotationOk(
          attachmentSha256: job.attachmentSha256,
          lang: job.lang,
          modelName: kUrlEnrichmentModelName,
          payloadJson: payload,
          nowMs: nowMs,
        );

        final title = (extracted.title ?? '').trim();
        if (title.isNotEmpty) {
          await store.upsertAttachmentTitle(
            attachmentSha256: job.attachmentSha256,
            title: title,
          );
        }

        processed += 1;
      } catch (e) {
        final attempts = job.attempts + 1;
        final nextRetryAtMs = nowMs + _backoffMs(attempts);
        await store.markAnnotationFailed(
          attachmentSha256: job.attachmentSha256,
          error: e.toString(),
          attempts: attempts,
          nextRetryAtMs: nextRetryAtMs,
          nowMs: nowMs,
        );
      }
    }

    return UrlEnrichmentRunResult(processed: processed);
  }

  static int _backoffMs(int attempts) {
    final clamped = attempts.clamp(1, 10);
    final seconds = 5 * (1 << (clamped - 1));
    return Duration(seconds: seconds).inMilliseconds;
  }

  static _UrlManifest _parseUrlManifest(Uint8List bytes) {
    final raw = utf8.decode(bytes, allowMalformed: false);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('url_manifest_invalid_json');
    }
    final schema = decoded['schema'];
    final url = decoded['url'];
    if (schema is! String || schema.trim() != kSecondLoopUrlManifestSchema) {
      throw StateError('url_manifest_schema_mismatch');
    }
    if (url is! String || url.trim().isEmpty) {
      throw StateError('url_manifest_missing_url');
    }
    return _UrlManifest(url: url.trim());
  }

  static Uri _parseHttpUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) throw StateError('url_invalid');
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw StateError('url_scheme_not_allowed');
    }
    if (uri.host.trim().isEmpty) throw StateError('url_host_required');
    return uri;
  }

  static String _decodeBestEffortUtf8(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _truncateUtf8ToMaxBytes(String input, int maxBytes) {
    final bytes = utf8.encode(input);
    if (bytes.length <= maxBytes) return input;

    var end = maxBytes;
    if (end >= bytes.length) end = bytes.length;
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end -= 1;
    }
    if (end <= 0) return '';
    return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
  }

  static _ExtractedHtml _extractFromHtml(
    String html, {
    required Uri baseUri,
  }) {
    final title = _extractTitle(html);
    final canonical = _extractCanonicalUrl(html, baseUri: baseUri);
    final site = baseUri.host.trim().isEmpty ? null : baseUri.host.trim();
    final text = _htmlToTextV1(html);
    return _ExtractedHtml(
      title: title,
      canonicalUrl: canonical,
      site: site,
      readableText: text,
    );
  }

  static String? _extractTitle(String html) {
    final ogTitle = RegExp(
      "<meta[^>]+property=[\"']og:title[\"'][^>]*content=[\"']([^\"']+)[\"']",
      caseSensitive: false,
    ).firstMatch(html);
    final og = ogTitle?.group(1);
    if (og != null && og.trim().isNotEmpty) {
      return _decodeHtmlEntities(og).trim();
    }

    final title = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    final raw = title?.group(1);
    if (raw == null) return null;
    final decoded = _decodeHtmlEntities(raw);
    final normalized = _normalizeWhitespaceKeepParagraphs(decoded).trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String? _extractCanonicalUrl(String html, {required Uri baseUri}) {
    final link = RegExp(
      "<link[^>]+rel=[\"']canonical[\"'][^>]*href=[\"']([^\"']+)[\"']",
      caseSensitive: false,
    ).firstMatch(html);
    final rawLink = link?.group(1);
    final ogUrl = RegExp(
      "<meta[^>]+property=[\"']og:url[\"'][^>]*content=[\"']([^\"']+)[\"']",
      caseSensitive: false,
    ).firstMatch(html);
    final rawOg = ogUrl?.group(1);

    final candidate = (rawLink ?? rawOg)?.trim();
    if (candidate == null || candidate.isEmpty) return null;

    final decoded = _decodeHtmlEntities(candidate).trim();
    final parsed = Uri.tryParse(decoded);
    if (parsed == null) return null;
    final resolved = parsed.hasScheme ? parsed : baseUri.resolveUri(parsed);
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
    if (resolved.host.trim().isEmpty) return null;
    return resolved.toString();
  }

  static String _htmlToTextV1(String html) {
    var s = html;
    s = _stripTagBlocks(s, 'script');
    s = _stripTagBlocks(s, 'style');
    s = _stripTagBlocks(s, 'noscript');

    const blockTags = <String>{
      'p',
      'div',
      'li',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'br',
      'hr',
      'pre',
      'blockquote',
      'tr',
      'td',
      'th',
      'section',
      'article',
    };

    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      if (s.codeUnitAt(i) != 0x3C /* < */) {
        out.writeCharCode(s.codeUnitAt(i));
        i += 1;
        continue;
      }

      final end = s.indexOf('>', i + 1);
      if (end < 0) break;

      final rawTag = s.substring(i + 1, end).trim();
      final tag =
          rawTag.startsWith('/') ? rawTag.substring(1).trimLeft() : rawTag;
      final name = tag.split(RegExp(r'\s+')).first;
      final local = name.split(':').last.toLowerCase();
      if (blockTags.contains(local)) {
        out.write('\n');
      }

      i = end + 1;
    }

    final decoded = _decodeHtmlEntities(out.toString());
    return _normalizeWhitespaceKeepParagraphs(decoded);
  }

  static String _stripTagBlocks(String html, String tag) {
    final lower = html.toLowerCase();
    final open = '<$tag';
    final close = '</$tag';

    final out = StringBuffer();
    var i = 0;
    while (i < html.length) {
      final start = lower.indexOf(open, i);
      if (start < 0) {
        out.write(html.substring(i));
        break;
      }
      out.write(html.substring(i, start));

      final afterOpen = start + open.length;
      final end = lower.indexOf(close, afterOpen);
      if (end < 0) break;
      final gt = lower.indexOf('>', end);
      if (gt < 0) break;
      i = gt + 1;
    }
    return out.toString();
  }

  static String _decodeHtmlEntities(String input) {
    final out = StringBuffer();
    var i = 0;
    while (i < input.length) {
      if (input.codeUnitAt(i) != 0x26 /* & */) {
        out.writeCharCode(input.codeUnitAt(i));
        i += 1;
        continue;
      }

      final semi = input.indexOf(';', i + 1);
      if (semi < 0 || semi - i > 12) {
        out.write('&');
        i += 1;
        continue;
      }

      final entity = input.substring(i + 1, semi);
      final decoded = switch (entity) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        '#39' => "'",
        'nbsp' => ' ',
        _ => null,
      };

      if (decoded != null) {
        out.write(decoded);
        i = semi + 1;
        continue;
      }

      if (entity.startsWith('#x') || entity.startsWith('#X')) {
        final code = int.tryParse(entity.substring(2), radix: 16);
        if (code != null) {
          out.write(String.fromCharCode(code));
          i = semi + 1;
          continue;
        }
      } else if (entity.startsWith('#')) {
        final code = int.tryParse(entity.substring(1));
        if (code != null) {
          out.write(String.fromCharCode(code));
          i = semi + 1;
          continue;
        }
      }

      out.write('&$entity;');
      i = semi + 1;
    }
    return out.toString();
  }

  static String _normalizeWhitespaceKeepParagraphs(String input) {
    final out = <int>[];
    var lastWasSpace = false;
    var newlineRun = 0;

    for (final rune in input.runes) {
      if (rune == 0x0D) continue; // \r

      if (rune == 0x0A) {
        // \n
        while (out.isNotEmpty && out.last == 0x20) {
          out.removeLast();
        }
        if (newlineRun < 2) {
          out.add(0x0A);
        }
        newlineRun += 1;
        lastWasSpace = false;
        continue;
      }

      final isWs = rune == 0x20 || rune == 0x09 || rune == 0x0B || rune == 0x0C;
      if (isWs) {
        if (newlineRun > 0) continue;
        if (out.isEmpty) continue;
        if (!lastWasSpace) {
          out.add(0x20);
          lastWasSpace = true;
        }
        continue;
      }

      out.add(rune);
      lastWasSpace = false;
      newlineRun = 0;
    }

    return String.fromCharCodes(out).trim();
  }
}

class _UrlManifest {
  const _UrlManifest({required this.url});

  final String url;
}

class _ExtractedHtml {
  const _ExtractedHtml({
    required this.title,
    required this.canonicalUrl,
    required this.site,
    required this.readableText,
  });

  final String? title;
  final String? canonicalUrl;
  final String? site;
  final String readableText;
}

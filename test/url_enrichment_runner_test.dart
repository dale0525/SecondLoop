import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/url_enrichment/url_enrichment_runner.dart';

final class _MemStore implements UrlEnrichmentStore {
  _MemStore({
    required this.jobs,
    required this.bytesBySha,
  });

  final List<UrlEnrichmentJob> jobs;
  final Map<String, Uint8List> bytesBySha;

  final Map<String, String> okPayloadBySha = <String, String>{};
  final Map<String, String> failedBySha = <String, String>{};
  final Map<String, String> titleBySha = <String, String>{};

  @override
  Future<List<UrlEnrichmentJob>> listDueUrlAnnotations({
    required int nowMs,
    int limit = 5,
  }) async {
    return jobs
        .where((j) => j.nextRetryAtMs == null || j.nextRetryAtMs! <= nowMs)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<Uint8List> readAttachmentBytes(
      {required String attachmentSha256}) async {
    final bytes = bytesBySha[attachmentSha256];
    if (bytes == null) {
      throw StateError('missing_bytes:$attachmentSha256');
    }
    return bytes;
  }

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) async {
    okPayloadBySha[attachmentSha256] = payloadJson;
  }

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    failedBySha[attachmentSha256] = error;
  }

  @override
  Future<void> upsertAttachmentTitle({
    required String attachmentSha256,
    required String title,
  }) async {
    titleBySha[attachmentSha256] = title;
  }
}

final class _FakeFetcher implements UrlEnrichmentFetcher {
  _FakeFetcher({required this.response});

  final UrlFetchResponse response;

  @override
  Future<UrlFetchResponse> fetch(Uri uri) async => response;
}

final class _FakeEnhancer implements UrlEnrichmentEnhancer {
  _FakeEnhancer({
    required this.modelName,
    required this.source,
    this.result,
    this.error,
  });

  @override
  final String modelName;

  @override
  final String source;

  final UrlEnrichmentEnhancerResult? result;
  final Object? error;

  @override
  Future<UrlEnrichmentEnhancerResult?> enhance({
    required String originalUrl,
    required String finalUrl,
    required String site,
    required String? title,
    required String readableTextExcerpt,
    required String readableTextFull,
  }) async {
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  test('enriches URL manifest: title + canonical + text excerpt/full',
      () async {
    final manifest = jsonEncode({
      'schema': kSecondLoopUrlManifestSchema,
      'url': 'https://example.com/page',
    });

    final store = _MemStore(
      jobs: const [
        UrlEnrichmentJob(
          attachmentSha256: 'a',
          lang: 'und',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      bytesBySha: {
        'a': Uint8List.fromList(utf8.encode(manifest)),
      },
    );

    const html = '''
<html>
  <head>
    <title>Hi &amp; Bye</title>
    <link rel="canonical" href="/canon" />
  </head>
  <body>
    <p>Hello&nbsp;World</p>
    <script>bad()</script>
    <div>More</div>
  </body>
</html>
''';

    final fetcher = _FakeFetcher(
      response: UrlFetchResponse(
        finalUri: Uri.parse('https://example.com/page'),
        statusCode: 200,
        contentType: 'text/html',
        bodyBytes: Uint8List.fromList(utf8.encode(html)),
      ),
    );

    final runner =
        UrlEnrichmentRunner(store: store, fetcher: fetcher, nowMs: () => 1000);
    final result = await runner.runOnce();
    expect(result.didEnrichAny, isTrue);

    final payloadRaw = store.okPayloadBySha['a'];
    expect(payloadRaw, isNotNull);
    final payload = jsonDecode(payloadRaw!) as Map;
    expect(payload['schema'], kSecondLoopUrlEnrichmentSchema);
    expect(payload['title'], 'Hi & Bye');
    expect(payload['site'], 'example.com');
    expect(payload['canonical_url'], 'https://example.com/canon');
    expect(
        (payload['readable_text_excerpt'] as String), contains('Hello World'));
    expect((payload['readable_text_full'] as String), contains('More'));
    expect((payload['readable_text_full'] as String), isNot(contains('bad')));

    expect(store.titleBySha['a'], 'Hi & Bye');
    expect(store.failedBySha, isEmpty);
  });

  test('uses enhancer output and model/source when enhancer succeeds',
      () async {
    final manifest = jsonEncode({
      'schema': kSecondLoopUrlManifestSchema,
      'url': 'https://example.com/page',
    });

    final store = _MemStore(
      jobs: const [
        UrlEnrichmentJob(
          attachmentSha256: 'b',
          lang: 'und',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      bytesBySha: {
        'b': Uint8List.fromList(utf8.encode(manifest)),
      },
    );

    const html = '''
<html>
  <head><title>Local Title</title></head>
  <body><p>Local body</p></body>
</html>
''';

    final fetcher = _FakeFetcher(
      response: UrlFetchResponse(
        finalUri: Uri.parse('https://example.com/page'),
        statusCode: 200,
        contentType: 'text/html',
        bodyBytes: Uint8List.fromList(utf8.encode(html)),
      ),
    );

    final runner = UrlEnrichmentRunner(
      store: store,
      fetcher: fetcher,
      nowMs: () => 2000,
      enhancers: [
        _FakeEnhancer(
          modelName: 'url_enrich.cloud',
          source: 'cloud',
          result: const UrlEnrichmentEnhancerResult(
            title: 'Cloud Title',
            summary: 'Cloud summary',
            tags: ['news', 'example'],
          ),
        ),
      ],
    );

    final result = await runner.runOnce();
    expect(result.didEnrichAny, isTrue);

    final payloadRaw = store.okPayloadBySha['b'];
    expect(payloadRaw, isNotNull);
    final payload = jsonDecode(payloadRaw!) as Map;
    expect(payload['title'], 'Cloud Title');
    expect(payload['enrichment_source'], 'cloud');
    expect(payload['llm_summary'], 'Cloud summary');
    expect(payload['llm_tags'], const ['news', 'example']);
    expect(store.titleBySha['b'], 'Cloud Title');
  });

  test('falls back to next enhancer then local when needed', () async {
    final manifest = jsonEncode({
      'schema': kSecondLoopUrlManifestSchema,
      'url': 'https://example.com/page',
    });

    final store = _MemStore(
      jobs: const [
        UrlEnrichmentJob(
          attachmentSha256: 'c',
          lang: 'und',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      bytesBySha: {
        'c': Uint8List.fromList(utf8.encode(manifest)),
      },
    );

    const html = '''
<html>
  <head><title>Local Title</title></head>
  <body><p>Local body</p></body>
</html>
''';

    final fetcher = _FakeFetcher(
      response: UrlFetchResponse(
        finalUri: Uri.parse('https://example.com/page'),
        statusCode: 200,
        contentType: 'text/html',
        bodyBytes: Uint8List.fromList(utf8.encode(html)),
      ),
    );

    final runner = UrlEnrichmentRunner(
      store: store,
      fetcher: fetcher,
      nowMs: () => 3000,
      enhancers: [
        _FakeEnhancer(
          modelName: 'url_enrich.cloud',
          source: 'cloud',
          error: StateError('cloud_failed'),
        ),
        _FakeEnhancer(
          modelName: 'url_enrich.byok',
          source: 'byok',
          result: null,
        ),
      ],
    );

    final result = await runner.runOnce();
    expect(result.didEnrichAny, isTrue);

    final payloadRaw = store.okPayloadBySha['c'];
    expect(payloadRaw, isNotNull);
    final payload = jsonDecode(payloadRaw!) as Map;
    expect(payload['title'], 'Local Title');
    expect(payload['enrichment_source'], 'local');
    expect(payload.containsKey('llm_summary'), isFalse);
    expect(payload.containsKey('llm_tags'), isFalse);
    expect(store.titleBySha['c'], 'Local Title');
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/media_enrichment/media_enrichment_runner.dart';
import 'package:secondloop/src/rust/db.dart';

final class _MemStore implements MediaEnrichmentStore {
  _MemStore({
    required this.places,
    required this.annotations,
    required this.exifBySha,
    required this.bytesBySha,
  });

  final List<MediaEnrichmentPlaceItem> places;
  final List<MediaEnrichmentAnnotationItem> annotations;
  final Map<String, AttachmentExifMetadata> exifBySha;
  final Map<String, Uint8List> bytesBySha;

  final Map<String, String> placeOkPayloadBySha = <String, String>{};
  final Map<String, String> placeFailedBySha = <String, String>{};
  final Map<String, String> annotationOkPayloadBySha = <String, String>{};
  final Map<String, String> annotationFailedBySha = <String, String>{};

  @override
  Future<List<MediaEnrichmentPlaceItem>> listDuePlaces({
    required int nowMs,
    int limit = 5,
  }) async {
    return places
        .where((i) => i.nextRetryAtMs == null || i.nextRetryAtMs! <= nowMs)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<MediaEnrichmentAnnotationItem>> listDueAnnotations({
    required int nowMs,
    int limit = 5,
  }) async {
    return annotations
        .where((i) => i.nextRetryAtMs == null || i.nextRetryAtMs! <= nowMs)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata({
    required String attachmentSha256,
  }) async {
    return exifBySha[attachmentSha256];
  }

  @override
  Future<Uint8List> readAttachmentBytes({
    required String attachmentSha256,
  }) async {
    final bytes = bytesBySha[attachmentSha256];
    if (bytes == null) {
      throw StateError('missing_bytes:$attachmentSha256');
    }
    return bytes;
  }

  @override
  Future<void> markPlaceOk({
    required String attachmentSha256,
    required String lang,
    required String payloadJson,
    required int nowMs,
  }) async {
    placeOkPayloadBySha[attachmentSha256] = payloadJson;
  }

  @override
  Future<void> markPlaceFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    placeFailedBySha[attachmentSha256] = error;
  }

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) async {
    annotationOkPayloadBySha[attachmentSha256] = payloadJson;
  }

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    annotationFailedBySha[attachmentSha256] = error;
  }
}

final class _MemClient implements MediaEnrichmentClient {
  @override
  final String annotationModelName = 'test-model';

  bool reverseShouldFail = false;
  bool annotateShouldFail = false;

  int reverseCalls = 0;
  int annotateCalls = 0;
  String? lastAnnotateMimeType;

  @override
  Future<String> reverseGeocode({
    required double lat,
    required double lon,
    required String lang,
  }) async {
    reverseCalls += 1;
    if (reverseShouldFail) throw Exception('reverse_failed');
    return '{"display_name":"Seattle"}';
  }

  @override
  Future<String> annotateImage({
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    annotateCalls += 1;
    lastAnnotateMimeType = mimeType;
    if (annotateShouldFail) throw Exception('annotate_failed');
    return '{"caption_long":"a cat"}';
  }
}

void main() {
  test('offline => does not process anything', () async {
    final store = _MemStore(
      places: const [
        MediaEnrichmentPlaceItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      annotations: const [
        MediaEnrichmentAnnotationItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      exifBySha: const {
        'a': AttachmentExifMetadata(latitude: 1.0, longitude: 2.0),
      },
      bytesBySha: {
        'a': Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      },
    );
    final client = _MemClient();

    final runner = MediaEnrichmentRunner(
      store: store,
      client: client,
      settings: const MediaEnrichmentRunnerSettings(
        annotationEnabled: true,
        annotationWifiOnly: true,
      ),
      getNetwork: () async => MediaEnrichmentNetwork.offline,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.didEnrichAny, isFalse);
    expect(client.reverseCalls, 0);
    expect(client.annotateCalls, 0);
  });

  test('wifi => processes place + annotation', () async {
    final store = _MemStore(
      places: const [
        MediaEnrichmentPlaceItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      annotations: const [
        MediaEnrichmentAnnotationItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      exifBySha: const {
        'a': AttachmentExifMetadata(latitude: 1.0, longitude: 2.0),
      },
      bytesBySha: {
        'a': Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      },
    );
    final client = _MemClient();

    final runner = MediaEnrichmentRunner(
      store: store,
      client: client,
      settings: const MediaEnrichmentRunnerSettings(
        annotationEnabled: true,
        annotationWifiOnly: true,
      ),
      getNetwork: () async => MediaEnrichmentNetwork.wifi,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.processedPlaces, 1);
    expect(result.processedAnnotations, 1);
    expect(store.placeOkPayloadBySha['a'], isNotNull);
    expect(store.annotationOkPayloadBySha['a'], isNotNull);
    expect(client.reverseCalls, 1);
    expect(client.annotateCalls, 1);
  });

  test('cellular + annotation wifiOnly => place ok, annotation blocked',
      () async {
    final store = _MemStore(
      places: const [
        MediaEnrichmentPlaceItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      annotations: const [
        MediaEnrichmentAnnotationItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      exifBySha: const {
        'a': AttachmentExifMetadata(latitude: 1.0, longitude: 2.0),
      },
      bytesBySha: {
        'a': Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      },
    );
    final client = _MemClient();

    final runner = MediaEnrichmentRunner(
      store: store,
      client: client,
      settings: const MediaEnrichmentRunnerSettings(
        annotationEnabled: true,
        annotationWifiOnly: true,
      ),
      getNetwork: () async => MediaEnrichmentNetwork.cellular,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.processedPlaces, 1);
    expect(result.processedAnnotations, 0);
    expect(result.needsAnnotationCellularConfirmation, isTrue);
    expect(client.reverseCalls, 1);
    expect(client.annotateCalls, 0);
  });

  test('offline still processes local annotation fallback', () async {
    final store = _MemStore(
      places: const [],
      annotations: const [
        MediaEnrichmentAnnotationItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      exifBySha: const {},
      bytesBySha: {
        'a': Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      },
    );
    final client = _MemClient();

    final runner = MediaEnrichmentRunner(
      store: store,
      client: client,
      settings: const MediaEnrichmentRunnerSettings(
        annotationEnabled: true,
        annotationWifiOnly: true,
        annotationRequiresNetwork: false,
      ),
      getNetwork: () async => MediaEnrichmentNetwork.offline,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.processedPlaces, 0);
    expect(result.processedAnnotations, 1);
    expect(result.needsAnnotationCellularConfirmation, isFalse);
    expect(store.annotationOkPayloadBySha['a'], isNotNull);
    expect(client.annotateCalls, 1);
  });

  test('cellular wifi-only does not block local annotation fallback', () async {
    final store = _MemStore(
      places: const [],
      annotations: const [
        MediaEnrichmentAnnotationItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      exifBySha: const {},
      bytesBySha: {
        'a': Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      },
    );
    final client = _MemClient();

    final runner = MediaEnrichmentRunner(
      store: store,
      client: client,
      settings: const MediaEnrichmentRunnerSettings(
        annotationEnabled: true,
        annotationWifiOnly: true,
        annotationRequiresNetwork: false,
      ),
      getNetwork: () async => MediaEnrichmentNetwork.cellular,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.processedPlaces, 0);
    expect(result.processedAnnotations, 1);
    expect(result.needsAnnotationCellularConfirmation, isFalse);
    expect(store.annotationOkPayloadBySha['a'], isNotNull);
    expect(client.annotateCalls, 1);
  });

  test('local annotation fallback tolerates unknown image mime', () async {
    final store = _MemStore(
      places: const [],
      annotations: const [
        MediaEnrichmentAnnotationItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      exifBySha: const {},
      bytesBySha: {
        'a': Uint8List.fromList([0x00, 0x11, 0x22, 0x33]),
      },
    );
    final client = _MemClient();

    final runner = MediaEnrichmentRunner(
      store: store,
      client: client,
      settings: const MediaEnrichmentRunnerSettings(
        annotationEnabled: true,
        annotationWifiOnly: true,
        annotationRequiresNetwork: false,
      ),
      getNetwork: () async => MediaEnrichmentNetwork.wifi,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.processedAnnotations, 1);
    expect(store.annotationOkPayloadBySha['a'], isNotNull);
    expect(client.lastAnnotateMimeType, 'image/unknown');
  });

  test('failure => marks failed and schedules retry', () async {
    final store = _MemStore(
      places: const [
        MediaEnrichmentPlaceItem(
          attachmentSha256: 'a',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      annotations: const [],
      exifBySha: const {
        'a': AttachmentExifMetadata(latitude: 1.0, longitude: 2.0),
      },
      bytesBySha: {
        'a': Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      },
    );
    final client = _MemClient()..reverseShouldFail = true;

    final runner = MediaEnrichmentRunner(
      store: store,
      client: client,
      settings: const MediaEnrichmentRunnerSettings(
        annotationEnabled: false,
        annotationWifiOnly: true,
      ),
      getNetwork: () async => MediaEnrichmentNetwork.wifi,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.didEnrichAny, isFalse);
    expect(store.placeFailedBySha['a'], isNotNull);
    expect(client.reverseCalls, 1);
  });
}

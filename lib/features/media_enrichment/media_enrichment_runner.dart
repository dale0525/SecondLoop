import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/backend/native_backend.dart';
import '../../src/rust/db.dart';

enum MediaEnrichmentNetwork {
  offline,
  wifi,
  cellular,
  unknown,
}

final class MediaEnrichmentPlaceItem {
  const MediaEnrichmentPlaceItem({
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

final class MediaEnrichmentAnnotationItem {
  const MediaEnrichmentAnnotationItem({
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

abstract class MediaEnrichmentStore {
  Future<List<MediaEnrichmentPlaceItem>> listDuePlaces({
    required int nowMs,
    int limit = 5,
  });

  Future<List<MediaEnrichmentAnnotationItem>> listDueAnnotations({
    required int nowMs,
    int limit = 5,
  });

  Future<AttachmentExifMetadata?> readAttachmentExifMetadata({
    required String attachmentSha256,
  });

  Future<Uint8List> readAttachmentBytes({
    required String attachmentSha256,
  });

  Future<void> markPlaceOk({
    required String attachmentSha256,
    required String lang,
    required String payloadJson,
    required int nowMs,
  });

  Future<void> markPlaceFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  });

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
}

abstract class MediaEnrichmentClient {
  String get annotationModelName;

  Future<String> reverseGeocode({
    required double lat,
    required double lon,
    required String lang,
  });

  Future<String> annotateImage({
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  });
}

final class MediaEnrichmentRunnerSettings {
  const MediaEnrichmentRunnerSettings({
    required this.annotationEnabled,
    required this.annotationWifiOnly,
  });

  final bool annotationEnabled;
  final bool annotationWifiOnly;
}

final class MediaEnrichmentRunResult {
  const MediaEnrichmentRunResult({
    required this.processedPlaces,
    required this.processedAnnotations,
    required this.needsAnnotationCellularConfirmation,
  });

  final int processedPlaces;
  final int processedAnnotations;
  final bool needsAnnotationCellularConfirmation;

  bool get didEnrichAny => processedPlaces > 0 || processedAnnotations > 0;
}

typedef MediaEnrichmentNowMs = int Function();
typedef MediaEnrichmentNetworkProvider = Future<MediaEnrichmentNetwork>
    Function();

final class MediaEnrichmentRunner {
  MediaEnrichmentRunner({
    required this.store,
    required this.client,
    required this.settings,
    required this.getNetwork,
    MediaEnrichmentNowMs? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final MediaEnrichmentStore store;
  final MediaEnrichmentClient client;
  final MediaEnrichmentRunnerSettings settings;
  final MediaEnrichmentNetworkProvider getNetwork;
  final MediaEnrichmentNowMs _nowMs;

  Future<MediaEnrichmentRunResult> runOnce({
    bool allowAnnotationCellular = false,
  }) async {
    final nowMs = _nowMs();
    final network = await getNetwork();

    if (network == MediaEnrichmentNetwork.offline) {
      return const MediaEnrichmentRunResult(
        processedPlaces: 0,
        processedAnnotations: 0,
        needsAnnotationCellularConfirmation: false,
      );
    }

    var processedPlaces = 0;
    var processedAnnotations = 0;
    var needsAnnotationCellularConfirmation = false;

    final duePlaces = await store.listDuePlaces(nowMs: nowMs);
    for (final item in duePlaces) {
      if (item.status == 'ok') continue;
      try {
        final exif = await store.readAttachmentExifMetadata(
          attachmentSha256: item.attachmentSha256,
        );
        if (exif == null || exif.latitude == null || exif.longitude == null) {
          throw StateError('missing_exif_location:${item.attachmentSha256}');
        }
        final payloadJson = await client.reverseGeocode(
          lat: exif.latitude!,
          lon: exif.longitude!,
          lang: item.lang,
        );
        await store.markPlaceOk(
          attachmentSha256: item.attachmentSha256,
          lang: item.lang,
          payloadJson: payloadJson,
          nowMs: nowMs,
        );
        processedPlaces += 1;
      } catch (e) {
        final attempts = item.attempts + 1;
        final nextRetryAtMs = nowMs + _backoffMs(attempts);
        await store.markPlaceFailed(
          attachmentSha256: item.attachmentSha256,
          error: e.toString(),
          attempts: attempts,
          nextRetryAtMs: nextRetryAtMs,
          nowMs: nowMs,
        );
      }
    }

    final annotationAllowed = settings.annotationEnabled &&
        (!settings.annotationWifiOnly ||
            network == MediaEnrichmentNetwork.wifi ||
            (network == MediaEnrichmentNetwork.cellular &&
                allowAnnotationCellular));

    if (settings.annotationEnabled && !annotationAllowed) {
      final dueAnnotations = await store.listDueAnnotations(nowMs: nowMs);
      if (dueAnnotations.isNotEmpty) {
        needsAnnotationCellularConfirmation = true;
      }
    }

    if (annotationAllowed) {
      final dueAnnotations = await store.listDueAnnotations(nowMs: nowMs);
      for (final item in dueAnnotations) {
        if (item.status == 'ok') continue;
        try {
          final bytes = await store.readAttachmentBytes(
            attachmentSha256: item.attachmentSha256,
          );
          final mimeType = _sniffMimeType(bytes);
          final payloadJson = await client.annotateImage(
            lang: item.lang,
            mimeType: mimeType,
            imageBytes: bytes,
          );
          await store.markAnnotationOk(
            attachmentSha256: item.attachmentSha256,
            lang: item.lang,
            modelName: client.annotationModelName,
            payloadJson: payloadJson,
            nowMs: nowMs,
          );
          processedAnnotations += 1;
        } catch (e) {
          final attempts = item.attempts + 1;
          final nextRetryAtMs = nowMs + _backoffMs(attempts);
          await store.markAnnotationFailed(
            attachmentSha256: item.attachmentSha256,
            error: e.toString(),
            attempts: attempts,
            nextRetryAtMs: nextRetryAtMs,
            nowMs: nowMs,
          );
        }
      }
    }

    return MediaEnrichmentRunResult(
      processedPlaces: processedPlaces,
      processedAnnotations: processedAnnotations,
      needsAnnotationCellularConfirmation: needsAnnotationCellularConfirmation,
    );
  }

  static int _backoffMs(int attempts) {
    final clamped = attempts.clamp(1, 10);
    final seconds = 5 * (1 << (clamped - 1));
    return Duration(seconds: seconds).inMilliseconds;
  }

  static String _sniffMimeType(Uint8List bytes) {
    if (bytes.lengthInBytes >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (bytes.lengthInBytes >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }

    if (bytes.lengthInBytes >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    throw StateError('unknown_image_mime_type');
  }
}

final class BackendMediaEnrichmentStore implements MediaEnrichmentStore {
  BackendMediaEnrichmentStore({
    required this.backend,
    required Uint8List sessionKey,
  }) : _sessionKey = Uint8List.fromList(sessionKey);

  final NativeAppBackend backend;
  final Uint8List _sessionKey;

  @override
  Future<List<MediaEnrichmentPlaceItem>> listDuePlaces({
    required int nowMs,
    int limit = 5,
  }) async {
    final rows = await backend.listDueAttachmentPlaces(
      _sessionKey,
      nowMs: nowMs,
      limit: limit,
    );
    return rows
        .map(
          (r) => MediaEnrichmentPlaceItem(
            attachmentSha256: r.attachmentSha256,
            lang: r.lang,
            status: r.status,
            attempts: r.attempts,
            nextRetryAtMs: r.nextRetryAtMs,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MediaEnrichmentAnnotationItem>> listDueAnnotations({
    required int nowMs,
    int limit = 5,
  }) async {
    final rows = await backend.listDueAttachmentAnnotations(
      _sessionKey,
      nowMs: nowMs,
      limit: limit,
    );
    return rows
        .map(
          (r) => MediaEnrichmentAnnotationItem(
            attachmentSha256: r.attachmentSha256,
            lang: r.lang,
            status: r.status,
            attempts: r.attempts,
            nextRetryAtMs: r.nextRetryAtMs,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata({
    required String attachmentSha256,
  }) async {
    return backend.readAttachmentExifMetadata(
      _sessionKey,
      sha256: attachmentSha256,
    );
  }

  @override
  Future<Uint8List> readAttachmentBytes({
    required String attachmentSha256,
  }) async {
    return backend.readAttachmentBytes(
      _sessionKey,
      sha256: attachmentSha256,
    );
  }

  @override
  Future<void> markPlaceOk({
    required String attachmentSha256,
    required String lang,
    required String payloadJson,
    required int nowMs,
  }) async {
    await backend.markAttachmentPlaceOkJson(
      _sessionKey,
      attachmentSha256: attachmentSha256,
      lang: lang,
      payloadJson: payloadJson,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markPlaceFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    await backend.markAttachmentPlaceFailed(
      _sessionKey,
      attachmentSha256: attachmentSha256,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: error,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) async {
    await backend.markAttachmentAnnotationOkJson(
      _sessionKey,
      attachmentSha256: attachmentSha256,
      lang: lang,
      modelName: modelName,
      payloadJson: payloadJson,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    await backend.markAttachmentAnnotationFailed(
      _sessionKey,
      attachmentSha256: attachmentSha256,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: error,
      nowMs: nowMs,
    );
  }
}

final class CloudGatewayMediaEnrichmentClient implements MediaEnrichmentClient {
  CloudGatewayMediaEnrichmentClient({
    required this.backend,
    required this.gatewayBaseUrl,
    required this.idToken,
    required this.annotationModelName,
  });

  final NativeAppBackend backend;
  final String gatewayBaseUrl;
  final String idToken;

  @override
  final String annotationModelName;

  @override
  Future<String> reverseGeocode({
    required double lat,
    required double lon,
    required String lang,
  }) async {
    return backend.geoReverseCloudGateway(
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      lat: lat,
      lon: lon,
      lang: lang,
    );
  }

  @override
  Future<String> annotateImage({
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    return backend.mediaAnnotationCloudGateway(
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      modelName: annotationModelName,
      lang: lang,
      mimeType: mimeType,
      imageBytes: imageBytes,
    );
  }
}

final class ConnectivityMediaEnrichmentNetworkProvider {
  ConnectivityMediaEnrichmentNetworkProvider({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<MediaEnrichmentNetwork> call() async {
    final results = await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return MediaEnrichmentNetwork.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return MediaEnrichmentNetwork.cellular;
    }
    if (results.contains(ConnectivityResult.none)) {
      return MediaEnrichmentNetwork.offline;
    }
    return MediaEnrichmentNetwork.unknown;
  }
}

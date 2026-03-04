import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';

void main() {
  test('NativeAppBackend.releaseLocalEmbeddingModelIfIdle forwards args',
      () async {
    int? capturedIdleMs;
    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      dbReleaseLocalEmbeddingModelIfIdle: ({
        required String appDir,
        required List<int> key,
        required int maxIdleMs,
      }) async {
        capturedIdleMs = maxIdleMs;
        return true;
      },
    );

    await backend.releaseLocalEmbeddingModelIfIdle(
      Uint8List.fromList(List<int>.filled(32, 1)),
      maxIdleMs: 180000,
    );

    expect(capturedIdleMs, 180000);
  });
}

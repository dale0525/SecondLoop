import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/message_embeddings_index_gate.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  testWidgets(
      'MessageEmbeddingsIndexGate legacy local route does not drain embeddings',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_source_preference_v1': 'local',
      'embeddings_data_consent_v1': false,
    });

    var remaining = 3;
    var calls = 0;
    var releaseCalls = 0;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop-test',
      dbProcessPendingMessageEmbeddings: ({
        required String appDir,
        required List<int> key,
        required int limit,
      }) async {
        calls += 1;
        if (remaining <= 0) return 0;
        remaining -= 1;
        return 1;
      },
      dbReleaseLocalEmbeddingModelIfIdle: ({
        required String appDir,
        required List<int> key,
        required int maxIdleMs,
      }) async {
        releaseCalls += 1;
        return false;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const MessageEmbeddingsIndexGate(
              child: SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(calls, 0);

    await tester.pump(const Duration(seconds: 6));
    expect(calls, 0);
    expect(releaseCalls, greaterThanOrEqualTo(1));
  });

  testWidgets(
      'MessageEmbeddingsIndexGate remote route skips local indexing and triggers idle release',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_source_preference_v1': 'byok',
      'embeddings_data_consent_v1': false,
    });

    var localCalls = 0;
    var releaseCalls = 0;

    final backend = _FakeRemoteRouteNativeBackend(
      appDirProvider: () async => '/tmp/secondloop-test',
      embeddingProfiles: const <EmbeddingProfile>[
        EmbeddingProfile(
          id: 'embed_1',
          name: 'Active',
          providerType: 'openai-compatible',
          baseUrl: 'https://api.openai.com/v1',
          modelName: 'text-embedding-3-small',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      dbProcessPendingMessageEmbeddings: ({
        required String appDir,
        required List<int> key,
        required int limit,
      }) async {
        localCalls += 1;
        return 0;
      },
      dbReleaseLocalEmbeddingModelIfIdle: ({
        required String appDir,
        required List<int> key,
        required int maxIdleMs,
      }) async {
        releaseCalls += 1;
        return true;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const MessageEmbeddingsIndexGate(
              child: SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(localCalls, 0);
    expect(releaseCalls, 0);

    await tester.pump(const Duration(seconds: 3));
    expect(localCalls, 0);
    expect(releaseCalls, greaterThanOrEqualTo(1));
  });
}

final class _FakeRemoteRouteNativeBackend extends NativeAppBackend {
  _FakeRemoteRouteNativeBackend({
    required super.appDirProvider,
    required super.dbProcessPendingMessageEmbeddings,
    required super.dbReleaseLocalEmbeddingModelIfIdle,
    required this.embeddingProfiles,
  });

  final List<EmbeddingProfile> embeddingProfiles;

  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async {
    return embeddingProfiles;
  }
}

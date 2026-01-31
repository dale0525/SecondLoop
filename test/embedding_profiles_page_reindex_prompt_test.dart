import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/embedding_profiles_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

final class _CaptureBackend extends TestAppBackend {
  _CaptureBackend({required List<EmbeddingProfile> profiles})
      : _profiles = List<EmbeddingProfile>.from(profiles);

  final List<EmbeddingProfile> _profiles;
  int activateCalls = 0;
  int createCalls = 0;

  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async {
    return List<EmbeddingProfile>.from(_profiles);
  }

  @override
  Future<void> setActiveEmbeddingProfile(
      Uint8List key, String profileId) async {
    activateCalls++;
    for (var i = 0; i < _profiles.length; i++) {
      final p = _profiles[i];
      _profiles[i] = EmbeddingProfile(
        id: p.id,
        name: p.name,
        providerType: p.providerType,
        baseUrl: p.baseUrl,
        modelName: p.modelName,
        isActive: p.id == profileId,
        createdAtMs: p.createdAtMs,
        updatedAtMs: p.updatedAtMs,
      );
    }
  }

  @override
  Future<EmbeddingProfile> createEmbeddingProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async {
    createCalls++;
    final created = EmbeddingProfile(
      id: 'ep${_profiles.length + 1}',
      name: name,
      providerType: providerType,
      baseUrl: baseUrl,
      modelName: modelName,
      isActive: setActive,
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    if (setActive) {
      for (var i = 0; i < _profiles.length; i++) {
        final p = _profiles[i];
        _profiles[i] = EmbeddingProfile(
          id: p.id,
          name: p.name,
          providerType: p.providerType,
          baseUrl: p.baseUrl,
          modelName: p.modelName,
          isActive: false,
          createdAtMs: p.createdAtMs,
          updatedAtMs: p.updatedAtMs,
        );
      }
    }
    _profiles.insert(0, created);
    return created;
  }
}

void main() {
  testWidgets('Embedding profiles confirm before activate/create',
      (tester) async {
    final backend = _CaptureBackend(profiles: const [
      EmbeddingProfile(
        id: 'p1',
        name: 'P1',
        providerType: 'openai-compatible',
        baseUrl: 'https://example.com/v1',
        modelName: 'multilingual-e5-small',
        isActive: true,
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
      EmbeddingProfile(
        id: 'p2',
        name: 'P2',
        providerType: 'openai-compatible',
        baseUrl: 'https://example.com/v1',
        modelName: 'multilingual-e5-small',
        isActive: false,
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    ]);

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: EmbeddingProfilesPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Activate another profile should prompt first.
    await tester.tap(find.text('P2'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('embedding_profile_reindex_dialog')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('embedding_profile_reindex_cancel')));
    await tester.pumpAndSettle();
    expect(backend.activateCalls, 0);

    await tester.tap(find.text('P2'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('embedding_profile_reindex_confirm')));
    await tester.pumpAndSettle();
    expect(backend.activateCalls, 1);

    // Save & Activate should also prompt first.
    await tester.ensureVisible(find.byKey(const ValueKey('embedding_api_key')));
    await tester.enterText(
      find.byKey(const ValueKey('embedding_api_key')),
      'sk-test',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('embedding_profile_save_activate')),
    );
    await tester
        .tap(find.byKey(const ValueKey('embedding_profile_save_activate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('embedding_profile_reindex_dialog')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('embedding_profile_reindex_cancel')));
    await tester.pumpAndSettle();
    expect(backend.createCalls, 0);
  });
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/embedding_profiles_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Embedding profiles can highlight add-profile section on entry',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _NoEmbeddingProfileBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MediaQuery(
                data: MediaQueryData(disableAnimations: true),
                child: EmbeddingProfilesPage(
                  focusTarget: EmbeddingProfilesFocusTarget.addProfileForm,
                  highlightFocus: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(
          const ValueKey('embedding_profiles_focus_add_highlight_marker')),
      findsOneWidget,
    );
  });
}

final class _NoEmbeddingProfileBackend extends TestAppBackend {
  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async =>
      const <EmbeddingProfile>[];
}

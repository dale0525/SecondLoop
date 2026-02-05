import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/media_annotation/media_annotation_config_store.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/media_annotation_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

final class _FakeMediaAnnotationConfigStore
    implements MediaAnnotationConfigStore {
  _FakeMediaAnnotationConfigStore(this._config);

  MediaAnnotationConfig _config;
  final List<MediaAnnotationConfig> writes = <MediaAnnotationConfig>[];

  @override
  Future<MediaAnnotationConfig> read(Uint8List key) async => _config;

  @override
  Future<void> write(Uint8List key, MediaAnnotationConfig config) async {
    _config = config;
    writes.add(config);
  }
}

void main() {
  testWidgets('Media annotation settings shows two switches', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      const MediaAnnotationConfig(
        annotateEnabled: false,
        searchEnabled: false,
        allowCellular: false,
        providerMode: 'follow_ask_ai',
      ),
    );

    await tester.pumpWidget(
      SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: wrapWithI18n(
          MaterialApp(
            home: Scaffold(
              body: MediaAnnotationSettingsPage(configStore: store),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(MediaAnnotationSettingsPage.annotateSwitchKey),
        findsOneWidget);
    expect(find.byKey(MediaAnnotationSettingsPage.searchSwitchKey),
        findsOneWidget);
  });

  testWidgets('Search toggle asks for confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: false,
        allowCellular: false,
        providerMode: 'follow_ask_ai',
      ),
    );

    await tester.pumpWidget(
      SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: wrapWithI18n(
          MaterialApp(
            home: Scaffold(
              body: MediaAnnotationSettingsPage(configStore: store),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(MediaAnnotationSettingsPage.searchSwitchKey));
    await tester.pumpAndSettle();

    expect(find.byKey(MediaAnnotationSettingsPage.searchConfirmDialogKey),
        findsOneWidget);

    await tester
        .tap(find.byKey(MediaAnnotationSettingsPage.searchConfirmCancelKey));
    await tester.pumpAndSettle();

    expect(find.byKey(MediaAnnotationSettingsPage.searchConfirmDialogKey),
        findsNothing);
  });
}

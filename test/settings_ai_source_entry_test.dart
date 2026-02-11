import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/media_annotation_settings_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Settings includes AI source entry and opens unified page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(
              home: Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final aiEntry = find.byKey(const ValueKey('settings_ai_source'));
    await tester.dragUntilVisible(
      aiEntry,
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();

    expect(aiEntry, findsOneWidget);

    await tester.tap(aiEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_settings_section_ask_ai')),
        findsOneWidget);
  });

  testWidgets('Media understanding entry opens unified AI settings page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(
              home: Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mediaEntry = find.byKey(const ValueKey('settings_media_annotation'));
    await tester.dragUntilVisible(
      mediaEntry,
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();

    expect(mediaEntry, findsOneWidget);

    await tester.tap(mediaEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);

    final listView = find.byType(ListView).first;
    final mediaSection =
        find.byKey(const ValueKey('ai_settings_section_media_understanding'));
    await tester.dragUntilVisible(
      mediaSection,
      listView,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(mediaSection, findsOneWidget);

    final embeddedRoot =
        find.byKey(MediaAnnotationSettingsPage.embeddedRootKey);
    await tester.dragUntilVisible(
      embeddedRoot,
      listView,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(embeddedRoot, findsOneWidget);
  });
}

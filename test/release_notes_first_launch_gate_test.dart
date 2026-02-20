import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/release_notes_first_launch_gate.dart';
import 'package:secondloop/core/update/release_notes_service.dart';

import 'test_i18n.dart';

class _FakeReleaseNotesService extends ReleaseNotesService {
  _FakeReleaseNotesService({required this.result});

  final ReleaseNotesFetchResult result;
  int fetchCalls = 0;

  @override
  Future<ReleaseNotesFetchResult> fetchReleaseNotes({
    required String tag,
    required Locale locale,
  }) async {
    fetchCalls += 1;
    return result;
  }
}

void main() {
  Future<void> pumpGate(
    WidgetTester tester, {
    required _FakeReleaseNotesService service,
    required Future<AppRuntimeVersion> Function() versionLoader,
  }) {
    return tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: ReleaseNotesFirstLaunchGate(
            releaseNotesService: service,
            currentVersionLoader: versionLoader,
            enableInDebug: true,
            child: const Scaffold(
              body: Center(child: Text('home')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('does not show dialog on first launch of fresh install',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final service = _FakeReleaseNotesService(
      result: const ReleaseNotesFetchResult(),
    );

    await pumpGate(
      tester,
      service: service,
      versionLoader: () async =>
          const AppRuntimeVersion(version: '1.2.3', buildNumber: '45'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('release_notes_dialog')), findsNothing);
    expect(service.fetchCalls, 0);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ReleaseNotesFirstLaunchGate.lastShownVersionPrefsKey),
      '1.2.3+45',
    );
  });

  testWidgets('shows release notes dialog when version changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ReleaseNotesFirstLaunchGate.lastShownVersionPrefsKey: '1.2.2+44',
    });

    final service = _FakeReleaseNotesService(
      result: ReleaseNotesFetchResult(
        notes: const ReleaseNotes(
          version: 'v1.2.3',
          summary: '新增快速记录能力。',
          highlights: ['支持全局快捷键'],
          sections: [
            ReleaseNotesSection(title: '功能', items: ['支持全局快捷键']),
          ],
        ),
        sourceLocaleTag: 'zh-CN',
        releasePageUri: Uri.parse(
            'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3'),
      ),
    );

    await pumpGate(
      tester,
      service: service,
      versionLoader: () async =>
          const AppRuntimeVersion(version: '1.2.3', buildNumber: '45'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('release_notes_dialog')), findsOneWidget);
    expect(service.fetchCalls, 1);

    await tester.tap(find.byKey(const ValueKey('release_notes_close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('release_notes_dialog')), findsNothing);
  });

  testWidgets('skips dialog when current version already shown',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ReleaseNotesFirstLaunchGate.lastShownVersionPrefsKey: '1.2.3+45',
    });

    final service = _FakeReleaseNotesService(
      result: const ReleaseNotesFetchResult(),
    );

    await pumpGate(
      tester,
      service: service,
      versionLoader: () async =>
          const AppRuntimeVersion(version: '1.2.3', buildNumber: '45'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('release_notes_dialog')), findsNothing);
    expect(service.fetchCalls, 0);
  });
}

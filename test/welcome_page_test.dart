import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/features/welcome/welcome_page.dart';
import 'package:secondloop/features/welcome/welcome_status.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  Future<void> bringIntoView(WidgetTester tester, Finder target) async {
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isEmpty) return;
    await tester.dragUntilVisible(
      target,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpWelcomePage(
    WidgetTester tester, {
    AppBackend? backend,
    Uint8List? sessionKey,
    required VoidCallback onSkip,
    required VoidCallback onFinish,
    WelcomeGuideStatusLoader? statusLoader,
    WelcomeGuideUriLauncher? uriLauncher,
  }) async {
    Widget app = wrapWithI18n(
      MaterialApp(
        home: WelcomePage(
          onSkipForNow: onSkip,
          onFinishSetup: onFinish,
          statusLoader: statusLoader ?? loadWelcomeGuideStatus,
          uriLauncher: uriLauncher,
        ),
      ),
    );

    if (backend != null) {
      app = AppBackendScope(
        backend: backend,
        child: app,
      );
    }

    if (sessionKey != null) {
      app = SessionScope(
        sessionKey: sessionKey,
        lock: () {},
        child: app,
      );
    }

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('renders three setup cards and footer actions', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
    );

    expect(find.byKey(const ValueKey('welcome_guide_header_title')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_header_subtitle')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_ai')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('welcome_guide_card_sync')), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_card_permissions')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_skip')), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_finish')), findsOneWidget);
  });

  testWidgets('fires callbacks when tapping skip and finish', (tester) async {
    SharedPreferences.setMockInitialValues({});

    var skipTapped = false;
    var finishTapped = false;

    await pumpWelcomePage(
      tester,
      onSkip: () => skipTapped = true,
      onFinish: () => finishTapped = true,
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('welcome_guide_skip')));
    await tester.pump();

    expect(skipTapped, isTrue);

    await tester.tap(find.byKey(const ValueKey('welcome_guide_finish')));
    await tester.pump();

    expect(finishTapped, isTrue);
  });

  testWidgets('AI status shows ready when at least one route is available',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      backend: TestAppBackend(),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
      onSkip: () {},
      onFinish: () {},
    );

    expect(find.byKey(const ValueKey('welcome_guide_ai_status_ready')),
        findsOneWidget);
  });

  testWidgets('sync status shows ready when configured sync exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeWebdavBaseUrl('https://example.com/webdav');
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 9)));

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
    );

    expect(find.byKey(const ValueKey('welcome_guide_sync_status_ready')),
        findsOneWidget);
  });

  testWidgets('opens AI settings from AI card', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      backend: TestAppBackend(),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('welcome_guide_card_ai_open')));
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
  });

  testWidgets('opens sync settings from sync card', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      backend: TestAppBackend(),
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('welcome_guide_card_sync_open')));
    await tester.pumpAndSettle();

    expect(find.byType(SyncSettingsPage), findsOneWidget);
  });

  testWidgets('permissions section renders entries and taps launcher',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final launched = <Uri>[];

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
      uriLauncher: (uri) async {
        launched.add(uri);
        return true;
      },
    );

    expect(find.byKey(const ValueKey('welcome_guide_permission_microphone')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_notifications')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_exact_alarm')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_location')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_auto_start')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_guide_permission_battery')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('welcome_guide_permission_speech')),
      findsNothing,
    );

    await bringIntoView(
      tester,
      find.byKey(const ValueKey('welcome_guide_permission_microphone')),
    );
    await tester
        .tap(find.byKey(const ValueKey('welcome_guide_permission_microphone')));
    await tester.pumpAndSettle();

    expect(launched, isNotEmpty);
  });

  testWidgets('hides unsupported permission entries on Windows',
      (tester) async {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});

    try {
      await pumpWelcomePage(
        tester,
        onSkip: () {},
        onFinish: () {},
        statusLoader: (_) async => const WelcomeGuideStatus(
          aiReady: false,
          syncReady: false,
        ),
        uriLauncher: (_) async => true,
      );

      expect(
        find.byKey(const ValueKey('welcome_guide_permission_microphone')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_notifications')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_auto_start')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_exact_alarm')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_location')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('welcome_guide_permission_battery')),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets('shows snackbar when permission settings launch fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpWelcomePage(
      tester,
      onSkip: () {},
      onFinish: () {},
      statusLoader: (_) async => const WelcomeGuideStatus(
        aiReady: false,
        syncReady: false,
      ),
      uriLauncher: (_) async => false,
    );

    await bringIntoView(
      tester,
      find.byKey(const ValueKey('welcome_guide_permission_exact_alarm')),
    );
    await tester.tap(
        find.byKey(const ValueKey('welcome_guide_permission_exact_alarm')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('welcome_guide_permission_launch_failed')),
      findsOneWidget,
    );
  });
}

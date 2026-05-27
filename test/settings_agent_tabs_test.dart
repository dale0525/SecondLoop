import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/theme_mode_prefs.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/desktop/desktop_boot_prefs.dart';
import 'package:secondloop/core/desktop/desktop_quick_capture_hotkey_prefs.dart';
import 'package:secondloop/core/notifications/review_reminder_in_app_fallback_prefs.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/update/update_badge_prefs.dart';
import 'package:secondloop/i18n/locale_prefs.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/features/settings/agent_settings_page.dart';
import 'package:secondloop/features/settings/settings_ui.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  const desktopCapabilities = AppPlatformCapabilities(
    supportsDesktopHotkey: true,
    supportsAudioRecording: true,
    supportsDesktopDrop: true,
    supportsDesktopBootSettings: true,
    supportsCameraCapture: false,
    usesCloudSessionModel: false,
  );

  const mobileCapabilities = AppPlatformCapabilities(
    supportsDesktopHotkey: false,
    supportsAudioRecording: true,
    supportsDesktopDrop: false,
    supportsDesktopBootSettings: false,
    supportsCameraCapture: true,
    usesCloudSessionModel: false,
  );

  Future<void> pumpSettingsPage(
    WidgetTester tester, {
    AppPlatformCapabilities capabilities = desktopCapabilities,
    Map<String, Object> prefs = const {},
    Future<void> Function()? beforePump,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    LocaleSettings.setLocale(AppLocale.en);
    AppLocaleBootstrap.resetForTests();
    AppThemeModePrefs.resetForTests();
    UpdateBadgePrefs.resetForTests();
    ReviewReminderInAppFallbackPrefs.value.value =
        ReviewReminderInAppFallbackPrefs.defaultValue;
    DesktopBootPrefs.value.value = DesktopBootConfig.defaults;
    DesktopQuickCaptureHotkeyPrefs.value.value = null;
    await AppThemeModePrefs.ensureInitialized();
    await beforePump?.call();
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppPlatformCapabilityScope(
            capabilities: capabilities,
            child: AppBackendScope(
              backend: TestAppBackend(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AgentSettingsPage(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectSettingsTab(WidgetTester tester, String label) async {
    final tab = find.text(label);
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  testWidgets('AgentSettingsPage shows top tabs without duplicate side tabs',
      (tester) async {
    await pumpSettingsPage(tester);

    expect(find.byType(SettingsPageShell), findsOneWidget);
    expect(find.byType(SettingsSection), findsWidgets);
    expect(find.byKey(const ValueKey('agent_tab_general_selected')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings_theme_mode')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_language')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('settings_review_reminder_in_app_fallback_switch'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings_actions_review_morning_time')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings_actions_review_day_end_time')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings_actions_review_weekly_time')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings_start_with_system_switch')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings_silent_startup_switch')),
        findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('settings_keep_running_in_background_switch'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings_quick_capture_hotkey')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings_about')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_reopen_welcome_guide')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings_diagnostics')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent_settings_open_cloud_account')),
        findsNothing);
    expect(find.byKey(const ValueKey('agent_settings_open_runtime_mode')),
        findsNothing);
    expect(find.byKey(const ValueKey('agent_settings_open_ai_settings')),
        findsNothing);
    expect(find.byKey(const ValueKey('agent_settings_open_diagnostics')),
        findsNothing);
    expect(find.text('General'), findsWidgets);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_side_tab_list')), findsNothing);
  });

  testWidgets('AgentSettingsPage theme mode row persists selection',
      (tester) async {
    await pumpSettingsPage(tester);

    expect(find.byKey(const ValueKey('settings_theme_mode')), findsOneWidget);
    expect(AppThemeModePrefs.value.value, ThemeMode.system);

    await tester.tap(find.byKey(const ValueKey('settings_theme_mode')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('settings_theme_mode_option_dark')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppThemeModePrefs.prefsKey), 'dark');
    expect(AppThemeModePrefs.value.value, ThemeMode.dark);
  });

  testWidgets('AgentSettingsPage language selection persists override',
      (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.byKey(const ValueKey('settings_language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simplified Chinese'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAppLocaleOverridePrefsKey), 'zh-CN');
  });

  testWidgets('AgentSettingsPage review reminder fallback persists',
      (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(
      find.byKey(
        const ValueKey('settings_review_reminder_in_app_fallback_switch'),
      ),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ReviewReminderInAppFallbackPrefs.prefsKey), isFalse);
  });

  testWidgets('AgentSettingsPage shows update badge on About entry',
      (tester) async {
    await pumpSettingsPage(
      tester,
      beforePump: () => UpdateBadgePrefs.setAvailableVersion('v1.1.0'),
    );

    expect(find.byKey(const ValueKey('settings_about_update_badge')),
        findsOneWidget);
  });

  testWidgets('AgentSettingsPage gates desktop-only rows by capability',
      (tester) async {
    await pumpSettingsPage(tester, capabilities: mobileCapabilities);

    expect(find.byKey(const ValueKey('settings_start_with_system_switch')),
        findsNothing);
    expect(find.byKey(const ValueKey('settings_silent_startup_switch')),
        findsNothing);
    expect(
      find.byKey(
        const ValueKey('settings_keep_running_in_background_switch'),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('settings_quick_capture_hotkey')),
        findsNothing);
  });

  testWidgets('Account tab owns profile plan billing and security only',
      (tester) async {
    await pumpSettingsPage(tester);

    await selectSettingsTab(tester, 'Account');

    expect(find.byKey(const ValueKey('cloud_sign_in')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_sign_up')), findsOneWidget);
    expect(find.text('Runtime mode'), findsNothing);
    expect(find.text('Allowed actions'), findsNothing);
  });

  testWidgets('Connection tab owns runtime setup and connection health only',
      (tester) async {
    await pumpSettingsPage(tester);

    await selectSettingsTab(tester, 'Connection');

    expect(find.byKey(const ValueKey('runtime_mode_self_managed')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('runtime_mode_managed_pro')), findsOneWidget);
    expect(find.text('Allowed actions'), findsNothing);
    expect(find.text('Activity transparency timeline'), findsNothing);
    expect(
      find.byKey(const ValueKey('agent_settings_open_runtime_mode')),
      findsNothing,
    );
  });

  testWidgets('Permissions tab owns allowed actions only', (tester) async {
    await pumpSettingsPage(tester);

    await selectSettingsTab(tester, 'Permissions');

    expect(find.text('Allowed actions'), findsOneWidget);
    expect(find.text('External writes and sends stay behind approval.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('ai_settings_home_ask_ai')), findsNothing);
    expect(find.byKey(const ValueKey('ai_settings_home_smart_organization')),
        findsNothing);
    expect(find.text('Runtime mode'), findsNothing);
    expect(find.text('Memory behavior toggles'), findsNothing);
  });

  testWidgets('Memory tab owns memory behavior toggles only', (tester) async {
    await pumpSettingsPage(tester);

    await selectSettingsTab(tester, 'Memory');

    expect(
        find.byKey(const ValueKey('agent_digest_regenerate')), findsOneWidget);
    expect(find.text('Allowed actions'), findsNothing);
    expect(find.text('Diagnostic export'), findsNothing);
  });

  testWidgets('Activity tab owns transparency timeline and diagnostics only',
      (tester) async {
    await pumpSettingsPage(tester);

    await selectSettingsTab(tester, 'Activity');

    expect(find.byKey(const ValueKey('diagnostics_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics_copy')), findsOneWidget);
    expect(find.text('Runtime mode'), findsNothing);
    expect(find.text('Memory behavior toggles'), findsNothing);
  });
}

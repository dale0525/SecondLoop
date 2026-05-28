import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/app_shell_style.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/update/update_badge_prefs.dart';
import 'package:secondloop/features/settings/cloud_runtime_mode_page.dart';
import 'package:secondloop/ui/sl_tokens.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
  });

  testWidgets('desktop AppShell exposes the canonical workbench destinations',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppShell(
            conversationTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_conversation_tab')),
            notesTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_notes_tab')),
            memoryTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_memory_tab')),
            reviewTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_review_tab')),
            settingsTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_settings_tab')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app_shell_sidebar')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Briefing'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Approvals'), findsOneWidget);
    expect(find.text('Connectors'), findsOneWidget);
    expect(find.byKey(const ValueKey('app_shell_desktop_quick_capture')),
        findsNothing);
  });

  testWidgets('mobile AppShell exposes the five agent destinations',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppShell(
              conversationTabBuilder: (_, __) =>
                  const SizedBox(key: ValueKey('agent_conversation_tab')),
              notesTabBuilder: (_, __) =>
                  const SizedBox(key: ValueKey('agent_notes_tab')),
              memoryTabBuilder: (_, __) =>
                  const SizedBox(key: ValueKey('agent_memory_tab')),
              reviewTabBuilder: (_, __) =>
                  const SizedBox(key: ValueKey('agent_review_tab')),
              settingsTabBuilder: (_, __) =>
                  const SizedBox(key: ValueKey('agent_settings_tab')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app_shell_bottom_nav')),
        findsOneWidget,
      );
      expect(find.text('Briefing'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Vault'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Briefing'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('agent_review_tab')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('desktop AppShell uses a wide workspace and branded sidebar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2048, 1365));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppShell(
            conversationTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_conversation_tab')),
            notesTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_notes_tab')),
            memoryTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_memory_tab')),
            reviewTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_review_tab')),
            settingsTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_settings_tab')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SecondLoop'), findsOneWidget);
    final shellWidth = tester
        .getSize(find.byKey(const ValueKey('app_shell_desktop_workbench')))
        .width;
    final sidebarWidth =
        tester.getSize(find.byKey(const ValueKey('app_shell_sidebar'))).width;

    expect(shellWidth - sidebarWidth, greaterThan(1600));
  });

  testWidgets('desktop AppShell labels stored self-managed runtime',
      (tester) async {
    await RuntimeConnectionStore().saveConnection(_selfManagedConnection);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppShell(
            conversationTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_conversation_tab')),
            notesTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_notes_tab')),
            memoryTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_memory_tab')),
            reviewTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_review_tab')),
            settingsTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_settings_tab')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Self-managed'), findsOneWidget);
    expect(find.text('Managed Pro'), findsNothing);
  });

  testWidgets('AppShell follows the active dark app theme', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: AppShell(
            conversationTabBuilder: (_, __) => Builder(
              builder: (context) {
                final tokens = SlTokens.of(context);
                return ColoredBox(
                  key: const ValueKey('agent_shell_palette_probe'),
                  color: tokens.surface,
                  child: Text(Theme.of(context).brightness.name),
                );
              },
            ),
            notesTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_notes_tab')),
            memoryTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_memory_tab')),
            reviewTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_review_tab')),
            settingsTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_settings_tab')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('dark'), findsOneWidget);
    final probe = tester.widget<ColoredBox>(find.byKey(const ValueKey(
      'agent_shell_palette_probe',
    )));
    expect(probe.color, AppShellPalette.darkPanel);
  });

  testWidgets('runtime mode tab inherits AppShell dark theme', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: AppShell(
            initialTab: AppTab.settings,
            conversationTabBuilder: (_, __) => const SizedBox.shrink(),
            notesTabBuilder: (_, __) => const SizedBox.shrink(),
            memoryTabBuilder: (_, __) => const SizedBox.shrink(),
            reviewTabBuilder: (_, __) => const SizedBox.shrink(),
            settingsTabBuilder: (_, __) => const CloudRuntimeModePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final runtimeContext =
        tester.element(find.byKey(const ValueKey('runtime_mode_page_root')));
    expect(Theme.of(runtimeContext).brightness, Brightness.dark);
  });
}

const _selfManagedConnection = CloudRuntimeConnection(
  profile: CloudRuntimeProfile(
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://user-runtime.example/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    authToken: 'runtime-token-1',
    capabilityManifestId: 'manifest-self-1',
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    vaultId: 'acct-1',
  ),
  manifest: CloudRuntimeManifest(
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://user-runtime.example/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    capabilities: CloudRuntimeRequiredCapabilities.all,
  ),
);

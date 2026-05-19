import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WebAppGate requires observable auth controllers at declaration time',
      () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(
      source,
      contains('final ObservableCloudAuthController authController;'),
    );
    expect(source, isNot(contains('_requireObservableAuthController')));
  });

  test('entitled web users are routed into shared AppShell', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, contains('child = AppBootstrap('));
    expect(source, contains('child: SessionBootstrap('));
    expect(source, contains('child: WebInitialSyncGate('));
    expect(source, contains('child: AppShell('));
    expect(
      source,
      contains("key: ValueKey<String>('web-main-shell-\$uid')"),
    );
    expect(source,
        contains('initialTab: widget.entryIntent == WebEntryIntent.manage'));
    expect(source, contains('? AppTab.settings'));
    expect(source, contains(': AppTab.chat'));
    expect(source, isNot(contains('WebChatPage(')));
  });

  test('web gate keeps public entry framed by WebPublicEntryScaffold', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, contains('child = WebPublicEntryScaffold('));
    expect(source, contains('signedIn: false,'));
    expect(source, contains('signedIn: true,'));
  });

  test('web app gate ignores stale sync-default priming completions', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, contains('identical(_syncDefaultsPriming, primingFuture)'));
  });

  test('obsolete web-only main-shell pages are removed from gate', () {
    final source = File('lib/web_app/web_app_gate.dart').readAsStringSync();

    expect(source, isNot(contains('class _WebFilesPage')));
    expect(source, isNot(contains('class _WebSettingsPage')));
    expect(source, isNot(contains('WebAppShell')));
  });

  test('web shell helper only keeps the public-entry panel frame', () {
    final source = File('lib/web_app/web_app_shell.dart').readAsStringSync();

    expect(source, contains('class WebAppPanelFrame'));
    expect(source, isNot(contains('class WebAppShellDestination')));
    expect(source, isNot(contains('class WebAppShell extends')));
    expect(source, isNot(contains('_WebAppShellRailTitle')));
  });

  test('obsolete web fallback helpers are removed', () {
    expect(File('lib/web_app/web_app_gate_helpers.dart').existsSync(), isFalse);
  });
}

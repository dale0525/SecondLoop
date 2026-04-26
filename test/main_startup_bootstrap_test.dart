import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/desktop/desktop_launch_args.dart';
import 'package:secondloop/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop hook invocation exits process with code 0', () async {
    var exitCode = -1;
    final handled = await app.handleDesktopHookInvocationAndExit(
      DesktopLaunchArgs.fromMainArgs(['--veloapp-install', '1.2.3']),
      exitProcess: (code) => exitCode = code,
    );

    expect(handled, true);
    expect(exitCode, 0);
  });

  test('Velopack uninstall hook cleans residue before exiting', () async {
    var cleanupCalled = false;
    var exitCode = -1;

    final handled = await app.handleDesktopHookInvocationAndExit(
      DesktopLaunchArgs.fromMainArgs(['--veloapp-uninstall', '1.2.3']),
      velopackUninstallCleanup: () async {
        cleanupCalled = true;
      },
      exitProcess: (code) => exitCode = code,
    );

    expect(handled, true);
    expect(cleanupCalled, true);
    expect(exitCode, 0);
  });

  test('Velopack uninstall hook exits even when cleanup fails', () async {
    var exitCode = -1;

    final handled = await app.handleDesktopHookInvocationAndExit(
      DesktopLaunchArgs.fromMainArgs(['--veloapp-uninstall', '1.2.3']),
      velopackUninstallCleanup: () async {
        throw StateError('cleanup failed');
      },
      exitProcess: (code) => exitCode = code,
    );

    expect(handled, true);
    expect(exitCode, 0);
  });

  test('non-uninstall Velopack hooks do not run uninstall cleanup', () async {
    var cleanupCalled = false;
    var exitCode = -1;

    final handled = await app.handleDesktopHookInvocationAndExit(
      DesktopLaunchArgs.fromMainArgs(['--veloapp-updated', '1.2.3']),
      velopackUninstallCleanup: () async {
        cleanupCalled = true;
      },
      exitProcess: (code) => exitCode = code,
    );

    expect(handled, true);
    expect(cleanupCalled, false);
    expect(exitCode, 0);
  });

  test('non-hook launch does not trigger process exit', () async {
    var exitCalled = false;
    final handled = await app.handleDesktopHookInvocationAndExit(
      DesktopLaunchArgs.fromMainArgs(['--foo']),
      exitProcess: (_) => exitCalled = true,
    );

    expect(handled, false);
    expect(exitCalled, false);
  });

  test('runs startup tasks in order', () async {
    final calls = <String>[];

    await app.runStartupBootstrap(
      initializeBackgroundSync: () async {
        calls.add('init');
      },
      refreshBackgroundSyncSchedule: () async {
        calls.add('refresh');
      },
      initializeLocalePrefs: () async {
        calls.add('locale');
      },
      taskTimeout: const Duration(milliseconds: 10),
    );

    expect(calls, <String>['init', 'refresh', 'locale']);
  });

  test('continues startup when a task throws', () async {
    final calls = <String>[];
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    await app.runStartupBootstrap(
      initializeBackgroundSync: () async {
        calls.add('init');
        throw StateError('boom');
      },
      refreshBackgroundSyncSchedule: () async {
        calls.add('refresh');
      },
      initializeLocalePrefs: () async {
        calls.add('locale');
      },
      taskTimeout: const Duration(milliseconds: 10),
    );

    expect(calls, <String>['init', 'refresh', 'locale']);
    expect(errors, hasLength(1));
    expect(errors.single.exceptionAsString(), contains('boom'));
  });

  test('continues startup when a task times out', () async {
    final calls = <String>[];
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    await app.runStartupBootstrap(
      initializeBackgroundSync: () async {
        calls.add('init');
        await Completer<void>().future;
      },
      refreshBackgroundSyncSchedule: () async {
        calls.add('refresh');
      },
      initializeLocalePrefs: () async {
        calls.add('locale');
      },
      taskTimeout: const Duration(milliseconds: 10),
    );

    expect(calls, <String>['init', 'refresh', 'locale']);
    expect(errors, hasLength(1));
    expect(errors.single.exception, isA<TimeoutException>());
  });
}

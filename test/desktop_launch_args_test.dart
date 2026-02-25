import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/desktop/desktop_launch_args.dart';

void main() {
  test('silent startup arg enables silentStartupRequested', () {
    final args = DesktopLaunchArgs.fromMainArgs([
      '--foo',
      kDesktopSilentStartupArg,
    ]);

    expect(args.silentStartupRequested, true);
  });

  test('without silent startup arg defaults to false', () {
    final args = DesktopLaunchArgs.fromMainArgs(['--foo']);

    expect(args.silentStartupRequested, false);
  });

  test('detects Velopack install hook invocation', () {
    final args = DesktopLaunchArgs.fromMainArgs([
      '--veloapp-install',
      '1.2.3',
    ]);

    expect(args.velopackHookInvocationRequested, true);
    expect(args.shouldExitBeforeLaunchingApp, true);
  });

  test('Velopack hook detection is case-insensitive', () {
    final args = DesktopLaunchArgs.fromMainArgs(['--VELOAPP-UPDATED', '1.2.3']);

    expect(args.velopackHookInvocationRequested, true);
    expect(args.shouldExitBeforeLaunchingApp, true);
  });
}

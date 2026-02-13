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
}

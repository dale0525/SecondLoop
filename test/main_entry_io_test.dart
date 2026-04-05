import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/platform/main_entry_io.dart' as io_entry;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initializes desktop window manager before running the app', () async {
    final calls = <String>[];

    await io_entry.runPlatformApp(
      const <String>[],
      initializeDesktopWindowManager: () async {
        calls.add('desktop');
      },
      startupBootstrapRunner: () async {
        calls.add('startup');
      },
      appRunner: (_) {
        calls.add('runApp');
      },
    );

    expect(calls, contains('desktop'));
    expect(calls, contains('runApp'));
    expect(calls.indexOf('desktop'), lessThan(calls.indexOf('runApp')));
  });

  test('continues to run the app when desktop window manager init fails',
      () async {
    final calls = <String>[];
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    await io_entry.runPlatformApp(
      const <String>[],
      initializeDesktopWindowManager: () async {
        calls.add('desktop');
        throw StateError('desktop bootstrap failed');
      },
      startupBootstrapRunner: () async {
        calls.add('startup');
      },
      appRunner: (_) {
        calls.add('runApp');
      },
    );

    expect(calls, containsAll(<String>['desktop', 'runApp']));
    expect(errors, hasLength(1));
    expect(
      errors.single.exceptionAsString(),
      contains('desktop bootstrap failed'),
    );
  });
}

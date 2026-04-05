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
}

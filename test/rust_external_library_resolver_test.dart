import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/rust_external_library_resolver.dart';

void main() {
  group('resolveRustLibraryPathForTest', () {
    test('returns sibling dll path for Windows executable', () {
      final path = resolveRustLibraryPathForTest(
        isWindows: true,
        resolvedExecutable:
            r'C:\Users\Admin\AppData\Local\Programs\SecondLoop\secondloop.exe',
        siblingExists: true,
      );

      expect(
        path,
        r'C:\Users\Admin\AppData\Local\Programs\SecondLoop\secondloop_rust.dll',
      );
    });

    test('returns null when sibling dll is missing', () {
      final path = resolveRustLibraryPathForTest(
        isWindows: true,
        resolvedExecutable:
            r'C:\Users\Admin\AppData\Local\Programs\SecondLoop\secondloop.exe',
        siblingExists: false,
      );

      expect(path, isNull);
    });

    test('returns null on non-Windows platforms', () {
      final path = resolveRustLibraryPathForTest(
        isWindows: false,
        resolvedExecutable:
            '/Applications/SecondLoop.app/Contents/MacOS/SecondLoop',
        siblingExists: true,
      );

      expect(path, isNull);
    });
  });
}

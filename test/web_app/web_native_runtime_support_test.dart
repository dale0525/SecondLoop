import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/web_app/web_native_runtime_support.dart';

void main() {
  test('resolveWebNativeRuntimeSupport requires browser capabilities', () {
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: true,
        sharedMemoryCapability: true,
      ),
      isTrue,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: false,
        sharedMemoryCapability: true,
      ),
      isFalse,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: true,
        sharedMemoryCapability: false,
      ),
      isFalse,
    );
  });

  test('legacy web native runtime defines fail fast', () {
    expect(
      () => validateNoLegacyWebNativeRuntimeOverrides(
        disableOverrideDefined: true,
        enableOverrideDefined: false,
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('SECONDLOOP_DISABLE_WEB_NATIVE_RUNTIME'),
        ),
      ),
    );
    expect(
      () => validateNoLegacyWebNativeRuntimeOverrides(
        disableOverrideDefined: false,
        enableOverrideDefined: true,
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('SECONDLOOP_ENABLE_WEB_NATIVE_RUNTIME'),
        ),
      ),
    );
  });
}

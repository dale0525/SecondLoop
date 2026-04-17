import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/web_app/web_native_runtime_support.dart';

void main() {
  test(
      'resolveWebNativeRuntimeSupport requires shared-memory capability and build opt-out',
      () {
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: true,
        sharedMemoryCapability: true,
        disableOverride: false,
      ),
      isTrue,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: false,
        sharedMemoryCapability: true,
        disableOverride: false,
      ),
      isFalse,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: true,
        sharedMemoryCapability: false,
        disableOverride: false,
      ),
      isFalse,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: true,
        sharedMemoryCapability: true,
        disableOverride: true,
      ),
      isFalse,
    );
  });
}

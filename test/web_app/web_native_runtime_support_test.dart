import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/web_app/web_native_runtime_support.dart';

void main() {
  test(
      'resolveWebNativeRuntimeSupport requires explicit opt-in and browser capabilities',
      () {
    expect(
      resolveWebNativeRuntimeSupport(
        runtimeOptIn: false,
        browserCapability: true,
        sharedMemoryCapability: true,
        disableOverride: false,
      ),
      isFalse,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        runtimeOptIn: true,
        browserCapability: true,
        sharedMemoryCapability: true,
        disableOverride: false,
      ),
      isTrue,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        runtimeOptIn: true,
        browserCapability: false,
        sharedMemoryCapability: true,
        disableOverride: false,
      ),
      isFalse,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        runtimeOptIn: true,
        browserCapability: true,
        sharedMemoryCapability: false,
        disableOverride: false,
      ),
      isFalse,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        runtimeOptIn: true,
        browserCapability: true,
        sharedMemoryCapability: true,
        disableOverride: true,
      ),
      isFalse,
    );
  });
}

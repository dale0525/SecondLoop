import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/web_app/web_native_runtime_support.dart';

void main() {
  test(
      'resolveWebNativeRuntimeSupport honors browser capability and build opt-out',
      () {
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: true,
        disableOverride: false,
      ),
      isTrue,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: false,
        disableOverride: false,
      ),
      isFalse,
    );
    expect(
      resolveWebNativeRuntimeSupport(
        browserCapability: true,
        disableOverride: true,
      ),
      isFalse,
    );
  });
}

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
}

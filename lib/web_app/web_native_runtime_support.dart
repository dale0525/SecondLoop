import 'web_native_runtime_support_stub.dart'
    if (dart.library.html) 'web_native_runtime_support_web.dart' as impl;

bool resolveWebNativeRuntimeSupport({
  required bool browserCapability,
  required bool sharedMemoryCapability,
}) {
  return browserCapability && sharedMemoryCapability;
}

bool browserSupportsWebNativeRuntime() => resolveWebNativeRuntimeSupport(
      browserCapability: impl.browserSupportsWebNativeRuntime(),
      sharedMemoryCapability: impl.browserSupportsSharedMemoryRuntime(),
    );

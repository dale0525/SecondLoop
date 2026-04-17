import 'web_native_runtime_support_stub.dart'
    if (dart.library.html) 'web_native_runtime_support_web.dart' as impl;

const bool _kDisableWebNativeRuntime = bool.fromEnvironment(
  'SECONDLOOP_DISABLE_WEB_NATIVE_RUNTIME',
);

bool resolveWebNativeRuntimeSupport({
  required bool browserCapability,
  required bool sharedMemoryCapability,
  bool disableOverride = _kDisableWebNativeRuntime,
}) {
  return !disableOverride && browserCapability && sharedMemoryCapability;
}

bool browserSupportsWebNativeRuntime() => resolveWebNativeRuntimeSupport(
      browserCapability: impl.browserSupportsWebNativeRuntime(),
      sharedMemoryCapability: impl.browserSupportsSharedMemoryRuntime(),
    );

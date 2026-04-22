import 'web_native_runtime_support_stub.dart'
    if (dart.library.html) 'web_native_runtime_support_web.dart' as impl;

const bool _kEnableWebNativeRuntime = bool.fromEnvironment(
  'SECONDLOOP_ENABLE_WEB_NATIVE_RUNTIME',
);

const bool _kDisableWebNativeRuntime = bool.fromEnvironment(
  'SECONDLOOP_DISABLE_WEB_NATIVE_RUNTIME',
);

bool resolveWebNativeRuntimeSupport({
  required bool runtimeOptIn,
  required bool browserCapability,
  required bool sharedMemoryCapability,
  bool disableOverride = _kDisableWebNativeRuntime,
}) {
  // The current managed-vault web-native path still requires a dedicated web
  // worker to keep sync XHR and SQLite runtime assumptions valid. Keep it
  // behind an explicit build opt-in until that worker-backed bridge ships.
  return runtimeOptIn &&
      !disableOverride &&
      browserCapability &&
      sharedMemoryCapability;
}

bool browserSupportsWebNativeRuntime() => resolveWebNativeRuntimeSupport(
      runtimeOptIn: _kEnableWebNativeRuntime,
      browserCapability: impl.browserSupportsWebNativeRuntime(),
      sharedMemoryCapability: impl.browserSupportsSharedMemoryRuntime(),
    );

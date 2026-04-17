import 'web_native_runtime_support_stub.dart'
    if (dart.library.html) 'web_native_runtime_support_web.dart' as impl;

const bool _kDisableWebNativeRuntime = bool.fromEnvironment(
  'SECONDLOOP_DISABLE_WEB_NATIVE_RUNTIME',
);

bool resolveWebNativeRuntimeSupport({
  required bool browserCapability,
  bool disableOverride = _kDisableWebNativeRuntime,
}) {
  return !disableOverride && browserCapability;
}

bool browserSupportsWebNativeRuntime() => resolveWebNativeRuntimeSupport(
      browserCapability: impl.browserSupportsWebNativeRuntime(),
    );

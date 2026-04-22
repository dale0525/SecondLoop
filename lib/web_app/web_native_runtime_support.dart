import 'web_native_runtime_support_stub.dart'
    if (dart.library.html) 'web_native_runtime_support_web.dart' as impl;

void validateNoLegacyWebNativeRuntimeOverrides({
  required bool disableOverrideDefined,
  required bool enableOverrideDefined,
}) {
  if (!disableOverrideDefined && !enableOverrideDefined) {
    return;
  }
  throw UnsupportedError(
    'Legacy web native runtime defines '
    'SECONDLOOP_DISABLE_WEB_NATIVE_RUNTIME and '
    'SECONDLOOP_ENABLE_WEB_NATIVE_RUNTIME have been removed. '
    '/app now requires the native web runtime path without fallback toggles.',
  );
}

void ensureNoLegacyWebNativeRuntimeOverrides() {
  validateNoLegacyWebNativeRuntimeOverrides(
    disableOverrideDefined: const bool.hasEnvironment(
      'SECONDLOOP_DISABLE_WEB_NATIVE_RUNTIME',
    ),
    enableOverrideDefined: const bool.hasEnvironment(
      'SECONDLOOP_ENABLE_WEB_NATIVE_RUNTIME',
    ),
  );
}

bool resolveWebNativeRuntimeSupport({
  required bool browserCapability,
  required bool sharedMemoryCapability,
}) {
  return browserCapability && sharedMemoryCapability;
}

bool browserSupportsWebNativeRuntime() {
  ensureNoLegacyWebNativeRuntimeOverrides();
  return resolveWebNativeRuntimeSupport(
    browserCapability: impl.browserSupportsWebNativeRuntime(),
    sharedMemoryCapability: impl.browserSupportsSharedMemoryRuntime(),
  );
}

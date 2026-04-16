import 'web_native_runtime_support_stub.dart'
    if (dart.library.html) 'web_native_runtime_support_web.dart' as impl;

bool browserSupportsWebNativeRuntime() =>
    impl.browserSupportsWebNativeRuntime();

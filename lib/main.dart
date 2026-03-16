export 'platform/main_entry_stub.dart'
    if (dart.library.html) 'platform/main_entry_web.dart'
    if (dart.library.io) 'platform/main_entry_io.dart'
    show MyApp, handleDesktopHookInvocationAndExit, runStartupBootstrap;

import 'platform/main_entry_stub.dart'
    if (dart.library.html) 'platform/main_entry_web.dart'
    if (dart.library.io) 'platform/main_entry_io.dart' as platform;

Future<void> main(List<String> args) => platform.runPlatformApp(args);

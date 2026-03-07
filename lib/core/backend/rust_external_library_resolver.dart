import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'rust_external_library_resolver_stub.dart'
    if (dart.library.io) 'rust_external_library_resolver_io.dart' as impl;

ExternalLibrary? resolveDesktopRustExternalLibrary() {
  return impl.resolveDesktopRustExternalLibrary();
}

String? resolveRustLibraryPathForTest({
  required bool isWindows,
  required String resolvedExecutable,
  required bool siblingExists,
}) {
  return impl.resolveRustLibraryPathForTest(
    isWindows: isWindows,
    resolvedExecutable: resolvedExecutable,
    siblingExists: siblingExists,
  );
}

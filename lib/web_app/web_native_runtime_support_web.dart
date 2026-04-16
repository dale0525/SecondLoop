// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:js_util' as js_util;

bool browserSupportsWebNativeRuntime() {
  try {
    final window = html.window;
    return js_util.getProperty<Object?>(window, 'indexedDB') != null;
  } catch (_) {
    return false;
  }
}

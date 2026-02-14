import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/desktop/desktop_window_manager_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    DesktopWindowManagerBootstrap.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      calls.add(methodCall.method);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initializes window manager channel once with taskbar bootstrap',
      () async {
    await DesktopWindowManagerBootstrap.ensureInitialized();
    await DesktopWindowManagerBootstrap.ensureInitialized();

    expect(calls, <String>['ensureInitialized', 'waitUntilReadyToShow']);
  });
}

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
      switch (methodCall.method) {
        case 'getBounds':
          return <String, double>{
            'x': 0,
            'y': 0,
            'width': 1280,
            'height': 720,
          };
        default:
          return true;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initializes window manager and waits until ready to show once',
      () async {
    await DesktopWindowManagerBootstrap.ensureInitialized();
    await DesktopWindowManagerBootstrap.waitUntilReadyToShow();
    await DesktopWindowManagerBootstrap.waitUntilReadyToShow();

    expect(
        calls.take(2), <String>['ensureInitialized', 'waitUntilReadyToShow']);
    expect(
      calls.where((method) => method == 'waitUntilReadyToShow'),
      hasLength(1),
    );
  });

  test('retries initialization after a failed attempt', () async {
    var failEnsureInitialized = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      calls.add(methodCall.method);
      if (methodCall.method == 'ensureInitialized' && failEnsureInitialized) {
        failEnsureInitialized = false;
        throw PlatformException(
          code: 'bootstrap-failed',
          message: 'failed to initialize window manager',
        );
      }

      switch (methodCall.method) {
        case 'getBounds':
          return <String, double>{
            'x': 0,
            'y': 0,
            'width': 1280,
            'height': 720,
          };
        default:
          return true;
      }
    });

    await expectLater(
      DesktopWindowManagerBootstrap.ensureInitialized(),
      throwsA(isA<PlatformException>()),
    );

    await DesktopWindowManagerBootstrap.ensureInitialized();
    await DesktopWindowManagerBootstrap.waitUntilReadyToShow();

    expect(
      calls.take(3),
      <String>[
        'ensureInitialized',
        'ensureInitialized',
        'waitUntilReadyToShow'
      ],
    );
  });
}

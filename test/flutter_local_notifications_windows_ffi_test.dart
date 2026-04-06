import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications_windows/src/ffi/bindings.dart'
    as windows_bindings;
import 'package:flutter_local_notifications_windows/src/plugin/ffi.dart'
    as windows_plugin;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

var _createPluginCalls = 0;
var _disposePluginCalls = 0;
var _initShouldSucceed = true;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  setUp(() {
    _createPluginCalls = 0;
    _disposePluginCalls = 0;
    _initShouldSucceed = true;
    windows_plugin.FlutterLocalNotificationsWindows.instance = null;
  });

  test('initialize disposes native plugin when native init reports failure',
      () async {
    _initShouldSucceed = false;

    final plugin = windows_plugin.FlutterLocalNotificationsWindows(
      library: ffi.DynamicLibrary.process(),
      bindings: windows_bindings.NotificationsPluginBindings.fromLookup(
        _lookupTestSymbol,
      ),
    );

    expect(
      await plugin.initialize(
        const WindowsInitializationSettings(
          appName: 'SecondLoop',
          appUserModelId: 'com.secondloop.secondloop',
          guid: 'd49b5b4a-0ea5-4e31-b5c9-945cc5405f59',
        ),
      ),
      isFalse,
    );

    expect(_createPluginCalls, 1);
    expect(_disposePluginCalls, 1);
    expect(windows_plugin.FlutterLocalNotificationsWindows.instance, isNull);
  });

  test('zonedSchedule throws when native Windows scheduling reports failure',
      () async {
    final plugin = windows_plugin.FlutterLocalNotificationsWindows(
      library: ffi.DynamicLibrary.process(),
      bindings: windows_bindings.NotificationsPluginBindings.fromLookup(
        _lookupTestSymbol,
      ),
    );

    expect(
      await plugin.initialize(
        const WindowsInitializationSettings(
          appName: 'SecondLoop',
          appUserModelId: 'com.secondloop.secondloop',
          guid: 'd49b5b4a-0ea5-4e31-b5c9-945cc5405f59',
        ),
        onNotificationReceived: (_) {},
      ),
      isTrue,
    );

    await expectLater(
      plugin.zonedSchedule(
        42,
        'title',
        'body',
        tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1)),
        null,
      ),
      throwsA(isA<Exception>()),
    );

    plugin.dispose();
  });

  test('dispose clears Windows plugin registration state before reinit',
      () async {
    final plugin = windows_plugin.FlutterLocalNotificationsWindows(
      library: ffi.DynamicLibrary.process(),
      bindings: windows_bindings.NotificationsPluginBindings.fromLookup(
        _lookupTestSymbol,
      ),
    );

    expect(
      await plugin.initialize(
        const WindowsInitializationSettings(
          appName: 'SecondLoop',
          appUserModelId: 'com.secondloop.secondloop',
          guid: 'd49b5b4a-0ea5-4e31-b5c9-945cc5405f59',
        ),
        onNotificationReceived: (_) {},
      ),
      isTrue,
    );

    expect(plugin.userCallback, isNotNull);
    expect(
        windows_plugin.FlutterLocalNotificationsWindows.instance, same(plugin));

    plugin.dispose();

    expect(plugin.userCallback, isNull);
    expect(windows_plugin.FlutterLocalNotificationsWindows.instance, isNull);

    expect(
      await plugin.initialize(
        const WindowsInitializationSettings(
          appName: 'SecondLoop',
          appUserModelId: 'com.secondloop.secondloop',
          guid: 'd49b5b4a-0ea5-4e31-b5c9-945cc5405f59',
        ),
        onNotificationReceived: (_) {},
      ),
      isTrue,
    );

    expect(plugin.userCallback, isNotNull);
    expect(
        windows_plugin.FlutterLocalNotificationsWindows.instance, same(plugin));

    plugin.dispose();
  });
}

ffi.Pointer<T> _lookupTestSymbol<T extends ffi.NativeType>(String symbolName) {
  return switch (symbolName) {
    'createPlugin' => ffi.Pointer.fromFunction<
        ffi.Pointer<windows_bindings.NativePlugin>
            Function()>(_createPlugin) as ffi.Pointer<T>,
    'disposePlugin' => ffi.Pointer.fromFunction<
            ffi.Void Function(
                ffi.Pointer<windows_bindings.NativePlugin>)>(_disposePlugin)
        as ffi.Pointer<T>,
    'init' => ffi.Pointer.fromFunction<
        ffi.Bool Function(
          ffi.Pointer<windows_bindings.NativePlugin>,
          ffi.Pointer<pkg_ffi.Utf8>,
          ffi.Pointer<pkg_ffi.Utf8>,
          ffi.Pointer<pkg_ffi.Utf8>,
          ffi.Pointer<pkg_ffi.Utf8>,
          windows_bindings.NativeNotificationCallback,
        )>(_init, false) as ffi.Pointer<T>,
    'scheduleNotification' => ffi.Pointer.fromFunction<
        ffi.Bool Function(
          ffi.Pointer<windows_bindings.NativePlugin>,
          ffi.Int,
          ffi.Pointer<pkg_ffi.Utf8>,
          ffi.Int,
        )>(_scheduleNotification, false) as ffi.Pointer<T>,
    _ => throw ArgumentError('Unexpected symbol lookup: $symbolName'),
  };
}

ffi.Pointer<windows_bindings.NativePlugin> _createPlugin() => (() {
      _createPluginCalls += 1;
      return ffi.Pointer<windows_bindings.NativePlugin>.fromAddress(1);
    })();

void _disposePlugin(ffi.Pointer<windows_bindings.NativePlugin> _) {
  _disposePluginCalls += 1;
}

bool _init(
  ffi.Pointer<windows_bindings.NativePlugin> _,
  ffi.Pointer<pkg_ffi.Utf8> __,
  ffi.Pointer<pkg_ffi.Utf8> ___,
  ffi.Pointer<pkg_ffi.Utf8> ____,
  ffi.Pointer<pkg_ffi.Utf8> _____,
  windows_bindings.NativeNotificationCallback ______,
) {
  return _initShouldSucceed;
}

bool _scheduleNotification(
  ffi.Pointer<windows_bindings.NativePlugin> _,
  int __,
  ffi.Pointer<pkg_ffi.Utf8> ___,
  int ____,
) {
  return false;
}

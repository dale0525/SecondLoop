import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runs startup tasks in order', () async {
    final calls = <String>[];

    await app.runStartupBootstrap(
      initializeBackgroundSync: () async {
        calls.add('init');
      },
      refreshBackgroundSyncSchedule: () async {
        calls.add('refresh');
      },
      initializeLocalePrefs: () async {
        calls.add('locale');
      },
      taskTimeout: const Duration(milliseconds: 10),
    );

    expect(calls, <String>['init', 'refresh', 'locale']);
  });

  test('continues startup when a task throws', () async {
    final calls = <String>[];
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    await app.runStartupBootstrap(
      initializeBackgroundSync: () async {
        calls.add('init');
        throw StateError('boom');
      },
      refreshBackgroundSyncSchedule: () async {
        calls.add('refresh');
      },
      initializeLocalePrefs: () async {
        calls.add('locale');
      },
      taskTimeout: const Duration(milliseconds: 10),
    );

    expect(calls, <String>['init', 'refresh', 'locale']);
    expect(errors, hasLength(1));
    expect(errors.single.exceptionAsString(), contains('boom'));
  });

  test('continues startup when a task times out', () async {
    final calls = <String>[];
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    await app.runStartupBootstrap(
      initializeBackgroundSync: () async {
        calls.add('init');
        await Completer<void>().future;
      },
      refreshBackgroundSyncSchedule: () async {
        calls.add('refresh');
      },
      initializeLocalePrefs: () async {
        calls.add('locale');
      },
      taskTimeout: const Duration(milliseconds: 10),
    );

    expect(calls, <String>['init', 'refresh', 'locale']);
    expect(errors, hasLength(1));
    expect(errors.single.exception, isA<TimeoutException>());
  });
}

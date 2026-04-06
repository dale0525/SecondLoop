// ignore_for_file: depend_on_referenced_packages

import 'dart:ffi' as ffi;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications_windows/src/plugin/ffi.dart'
    as windows_plugin;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:secondloop/core/notifications/review_notification_plan.dart';
import 'package:secondloop/core/notifications/review_reminder_notification_scheduler.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';

void main() {
  test('ensureInitialized requests exact alarm permission when unavailable',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final androidPlugin = _FakeAndroidNotificationsPlugin(
      canScheduleExactNotificationsResult: false,
    );
    FlutterLocalNotificationsPlatform.instance = androidPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await scheduler.ensureInitialized();

    expect(androidPlugin.initializeCalls, 1);
    expect(androidPlugin.getNotificationAppLaunchDetailsCalls, 1);
    expect(androidPlugin.requestNotificationsPermissionCalls, 1);
    expect(androidPlugin.canScheduleExactNotificationsCalls, 1);
    expect(androidPlugin.requestExactAlarmsPermissionCalls, 1);
  });

  test('ensureInitialized skips exact alarm request when already granted',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final androidPlugin = _FakeAndroidNotificationsPlugin(
      canScheduleExactNotificationsResult: true,
    );
    FlutterLocalNotificationsPlatform.instance = androidPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await scheduler.ensureInitialized();

    expect(androidPlugin.requestNotificationsPermissionCalls, 1);
    expect(androidPlugin.canScheduleExactNotificationsCalls, 1);
    expect(androidPlugin.requestExactAlarmsPermissionCalls, 0);
  });

  test(
      'ensureInitialized disables notifications when the current platform implementation is missing',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    FlutterLocalNotificationsPlatform.instance =
        _FallbackNotificationsPlatform();

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await scheduler.ensureInitialized();

    expect(scheduler.supportsSystemNotifications, isFalse);
  });

  test(
      'ensureInitialized marks notifications unavailable after init returns false and restores them on retry',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final windowsPlugin = _FakeAndroidNotificationsPlugin(
      canScheduleExactNotificationsResult: true,
      initializeResults: <bool>[false, true],
    );
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await expectLater(scheduler.ensureInitialized(), throwsStateError);
    expect(scheduler.supportsSystemNotifications, isFalse);

    await scheduler.ensureInitialized();

    expect(windowsPlugin.initializeCalls, 2);
    expect(windowsPlugin.getNotificationAppLaunchDetailsCalls, 1);
    expect(scheduler.supportsSystemNotifications, isTrue);
  });

  test(
      'schedule reports Windows scheduling failures and disables notifications',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final windowsPlugin = _ThrowingWindowsNotificationsPlugin();
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[
          ReviewReminderItem(
            todoId: 'todo:review',
            todoTitle: 'review this',
            sourceAtUtcMs: 10000,
            scheduleAtUtcMs: 20000,
            kind: ReviewReminderItemKind.reviewQueue,
            todoStatus: 'open',
          ),
        ],
      ),
    );

    expect(windowsPlugin.initializeCalls, 1);
    expect(windowsPlugin.zonedScheduleCalls, 1);
    expect(scheduler.supportsSystemNotifications, isFalse);
    expect(errors, hasLength(1));
    expect(
        errors.single.exceptionAsString(), contains('native schedule failed'));
  });

  test(
      'schedule retries Windows initialization after a transient scheduling failure',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final windowsPlugin = _ResetRequiredWindowsNotificationsPlugin();
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const item = ReviewReminderItem(
      todoId: 'todo:retry',
      todoTitle: 'retry this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[item],
      ),
    );

    expect(windowsPlugin.initializeAttempts, 1);
    expect(windowsPlugin.nativeInitializeCalls, 1);
    expect(windowsPlugin.zonedScheduleCalls, 1);
    expect(scheduler.supportsSystemNotifications, isFalse);

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[item],
      ),
    );

    expect(windowsPlugin.initializeAttempts, 2);
    expect(windowsPlugin.nativeInitializeCalls, 2);
    expect(windowsPlugin.disposeCalls, 1);
    expect(windowsPlugin.zonedScheduleCalls, 2);
    expect(scheduler.supportsSystemNotifications, isTrue);
    expect(errors, hasLength(1));
  });

  test(
      'schedule stops further Windows notifications and rolls back this batch after a failure',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final windowsPlugin = _SequencedWindowsNotificationsPlugin(
      scheduleOutcomes: <_WindowsScheduleOutcome>[
        _WindowsScheduleOutcome.success,
        _WindowsScheduleOutcome.throwError,
        _WindowsScheduleOutcome.success,
      ],
    );
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const first = ReviewReminderItem(
      todoId: 'todo:rollback-1',
      todoTitle: 'first',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const second = ReviewReminderItem(
      todoId: 'todo:rollback-2',
      todoTitle: 'second',
      sourceAtUtcMs: 10001,
      scheduleAtUtcMs: 20001,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const third = ReviewReminderItem(
      todoId: 'todo:rollback-3',
      todoTitle: 'third',
      sourceAtUtcMs: 10002,
      scheduleAtUtcMs: 20002,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 3,
        items: <ReviewReminderItem>[first, second, third],
      ),
    );

    final firstId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      first,
    );
    final thirdId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      third,
    );

    expect(windowsPlugin.zonedScheduleCalls, 2);
    expect(windowsPlugin.scheduledIds, <int>[firstId]);
    expect(windowsPlugin.cancelledIds, contains(firstId));
    expect(windowsPlugin.cancelledIds, isNot(contains(thirdId)));
    expect(errors, hasLength(1));
  });

  test('schedule restores the previous Windows batch when replacing it fails',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final windowsPlugin = _SequencedWindowsNotificationsPlugin(
      scheduleOutcomes: <_WindowsScheduleOutcome>[
        _WindowsScheduleOutcome.success,
        _WindowsScheduleOutcome.success,
        _WindowsScheduleOutcome.throwError,
        _WindowsScheduleOutcome.success,
      ],
    );
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const previous = ReviewReminderItem(
      todoId: 'todo:previous',
      todoTitle: 'previous',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const replacementOne = ReviewReminderItem(
      todoId: 'todo:new-1',
      todoTitle: 'new one',
      sourceAtUtcMs: 10001,
      scheduleAtUtcMs: 20001,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const replacementTwo = ReviewReminderItem(
      todoId: 'todo:new-2',
      todoTitle: 'new two',
      sourceAtUtcMs: 10002,
      scheduleAtUtcMs: 20002,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[previous],
      ),
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 2,
        items: <ReviewReminderItem>[replacementOne, replacementTwo],
      ),
    );

    final previousId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      previous,
    );
    final replacementOneId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      replacementOne,
    );
    final replacementTwoId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      replacementTwo,
    );

    expect(windowsPlugin.pendingIds, <int>{previousId});
    expect(windowsPlugin.cancelledIds, contains(previousId));
    expect(windowsPlugin.cancelledIds, contains(replacementOneId));
    expect(windowsPlugin.pendingIds, isNot(contains(replacementOneId)));
    expect(windowsPlugin.pendingIds, isNot(contains(replacementTwoId)));
    expect(errors, hasLength(1));
  });

  test('same todo keeps stable notification id across reminder updates', () {
    const first = ReviewReminderItem(
      todoId: 'todo:1',
      todoTitle: 'one',
      sourceAtUtcMs: 1000,
      scheduleAtUtcMs: 2000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const second = ReviewReminderItem(
      todoId: 'todo:1',
      todoTitle: 'one',
      sourceAtUtcMs: 3000,
      scheduleAtUtcMs: 4000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'in_progress',
    );
    const other = ReviewReminderItem(
      todoId: 'todo:2',
      todoTitle: 'two',
      sourceAtUtcMs: 3000,
      scheduleAtUtcMs: 4000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    expect(
      FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
        first,
      ),
      FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
        second,
      ),
    );
    expect(
      FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
        first,
      ),
      isNot(
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
          other,
        ),
      ),
    );
  });

  test('open reminders expose the same quick actions as task hub', () {
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .notificationQuickActionsForItem(item),
      <TaskHubQuickAction>[
        TaskHubQuickAction.start,
        TaskHubQuickAction.tomorrow,
        TaskHubQuickAction.today,
        TaskHubQuickAction.done,
      ],
    );
  });

  test('open reminders trim Android quick actions to the visible limit', () {
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .androidNotificationQuickActionsForItem(item),
      <TaskHubQuickAction>[
        TaskHubQuickAction.start,
        TaskHubQuickAction.done,
        TaskHubQuickAction.tomorrow,
      ],
    );
  });

  test('in-progress reminders expose the same quick actions as task hub', () {
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'in_progress',
    );

    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .notificationQuickActionsForItem(item),
      <TaskHubQuickAction>[
        TaskHubQuickAction.done,
        TaskHubQuickAction.tomorrow,
        TaskHubQuickAction.today,
      ],
    );
  });

  test('schedule adds Android quick actions matching task hub layout',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final androidPlugin = _FakeAndroidNotificationsPlugin(
      canScheduleExactNotificationsResult: true,
    );
    FlutterLocalNotificationsPlatform.instance = androidPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[item],
      ),
    );

    expect(androidPlugin.zonedScheduleCalls, 1);
    expect(
      androidPlugin.lastPayload,
      '${FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix}todo:review',
    );
    expect(
      androidPlugin.lastId,
      FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
        item,
      ),
    );

    final actions = androidPlugin.lastNotificationDetails?.actions;
    expect(actions, isNotNull);
    expect(actions!.map((action) => action.id), <String>[
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.start,
      ),
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.done,
      ),
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.tomorrow,
      ),
    ]);
  });

  test('notification details add Windows quick actions matching task hub', () {
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    final payload =
        FlutterLocalNotificationsReviewReminderScheduler.encodePayload(
      item,
    );

    final details = FlutterLocalNotificationsReviewReminderScheduler
            .notificationDetailsForItem(item)
        .windows;

    expect(details, isNotNull);
    expect(details!.actions.length, 4);
    expect(details.actions.map((action) => action.arguments), <String>[
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
          TaskHubQuickAction.start,
        ),
        payload,
      ),
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
          TaskHubQuickAction.tomorrow,
        ),
        payload,
      ),
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
          TaskHubQuickAction.today,
        ),
        payload,
      ),
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
          TaskHubQuickAction.done,
        ),
        payload,
      ),
    ]);
  });

  test('eventFromResponse decodes Windows quick action arguments', () {
    const payload =
        '${FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix}todo:review';
    final encoded = FlutterLocalNotificationsReviewReminderScheduler
        .encodeWindowsQuickActionArguments(
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.done,
      ),
      payload,
    );

    final event =
        FlutterLocalNotificationsReviewReminderScheduler.eventFromResponse(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        payload: encoded,
        actionId: encoded,
      ),
    );

    expect(event.payload, payload);
    expect(
      event.actionId,
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.done,
      ),
    );
  });

  test('legacy Windows app id list does not treat active channels as legacy',
      () {
    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .legacyWindowsAppUserModelIds(
        'com.secondloop.secondloop',
      ),
      isEmpty,
    );
    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .legacyWindowsAppUserModelIds(
        'com.secondloop.secondloopdev',
      ),
      isEmpty,
    );
  });
}

final class _FallbackNotificationsPlatform
    extends FlutterLocalNotificationsPlatform with MockPlatformInterfaceMixin {}

enum _WindowsScheduleOutcome { success, throwError }

final class _ThrowingWindowsNotificationsPlugin
    extends windows_plugin.FlutterLocalNotificationsWindows {
  _ThrowingWindowsNotificationsPlugin()
      : super(library: ffi.DynamicLibrary.process());

  int initializeCalls = 0;
  int zonedScheduleCalls = 0;

  @override
  Future<bool> initialize(
    WindowsInitializationSettings settings, {
    DidReceiveNotificationResponseCallback? onNotificationReceived,
  }) async {
    initializeCalls += 1;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    return null;
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    return const <PendingNotificationRequest>[];
  }

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    WindowsNotificationDetails? details, {
    String? payload,
  }) async {
    zonedScheduleCalls += 1;
    throw Exception('native schedule failed');
  }
}

final class _SequencedWindowsNotificationsPlugin
    extends windows_plugin.FlutterLocalNotificationsWindows {
  _SequencedWindowsNotificationsPlugin({
    required this.scheduleOutcomes,
  }) : super(library: ffi.DynamicLibrary.process());

  final List<_WindowsScheduleOutcome> scheduleOutcomes;

  int initializeCalls = 0;
  int zonedScheduleCalls = 0;
  final List<int> scheduledIds = <int>[];
  final List<int> cancelledIds = <int>[];
  final Set<int> pendingIds = <int>{};
  final Map<int, String?> payloadsById = <int, String?>{};

  @override
  Future<bool> initialize(
    WindowsInitializationSettings settings, {
    DidReceiveNotificationResponseCallback? onNotificationReceived,
  }) async {
    initializeCalls += 1;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    return null;
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    return <PendingNotificationRequest>[
      for (final notificationId in pendingIds)
        PendingNotificationRequest(
          notificationId,
          null,
          null,
          payloadsById[notificationId],
        ),
    ];
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
    pendingIds.remove(id);
    payloadsById.remove(id);
  }

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    WindowsNotificationDetails? details, {
    String? payload,
  }) async {
    zonedScheduleCalls += 1;
    final index = zonedScheduleCalls - 1;
    final outcome = index < scheduleOutcomes.length
        ? scheduleOutcomes[index]
        : scheduleOutcomes.last;
    switch (outcome) {
      case _WindowsScheduleOutcome.success:
        scheduledIds.add(id);
        pendingIds.add(id);
        payloadsById[id] = payload;
        return;
      case _WindowsScheduleOutcome.throwError:
        throw Exception('native schedule failed');
    }
  }
}

final class _ResetRequiredWindowsNotificationsPlugin
    extends windows_plugin.FlutterLocalNotificationsWindows {
  _ResetRequiredWindowsNotificationsPlugin()
      : super(library: ffi.DynamicLibrary.process());

  int initializeAttempts = 0;
  int nativeInitializeCalls = 0;
  int disposeCalls = 0;
  int zonedScheduleCalls = 0;

  bool _ready = false;
  bool _mustResetBeforeScheduling = false;

  @override
  Future<bool> initialize(
    WindowsInitializationSettings settings, {
    DidReceiveNotificationResponseCallback? onNotificationReceived,
  }) async {
    initializeAttempts += 1;
    if (_ready) {
      return true;
    }

    nativeInitializeCalls += 1;
    _ready = true;
    _mustResetBeforeScheduling = false;
    return true;
  }

  @override
  void dispose() {
    disposeCalls += 1;
    _ready = false;
    _mustResetBeforeScheduling = false;
  }

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    return null;
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    return const <PendingNotificationRequest>[];
  }

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    WindowsNotificationDetails? details, {
    String? payload,
  }) async {
    zonedScheduleCalls += 1;
    if (_mustResetBeforeScheduling) {
      throw Exception('stale native schedule failed');
    }

    if (zonedScheduleCalls == 1) {
      _mustResetBeforeScheduling = true;
      throw Exception('native schedule failed');
    }
  }
}

final class _FakeAndroidNotificationsPlugin
    extends AndroidFlutterLocalNotificationsPlugin {
  _FakeAndroidNotificationsPlugin({
    required this.canScheduleExactNotificationsResult,
    bool initializeResult = true,
    List<bool>? initializeResults,
  }) : initializeResults = initializeResults ?? <bool>[initializeResult];

  final bool canScheduleExactNotificationsResult;
  final List<bool> initializeResults;

  int initializeCalls = 0;
  int getNotificationAppLaunchDetailsCalls = 0;
  int requestNotificationsPermissionCalls = 0;
  int canScheduleExactNotificationsCalls = 0;
  int requestExactAlarmsPermissionCalls = 0;
  int zonedScheduleCalls = 0;
  int? lastId;
  String? lastPayload;
  AndroidNotificationDetails? lastNotificationDetails;

  @override
  Future<bool> initialize(
    AndroidInitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls += 1;
    final index = initializeCalls - 1;
    if (index < initializeResults.length) {
      return initializeResults[index];
    }
    return initializeResults.last;
  }

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    getNotificationAppLaunchDetailsCalls += 1;
    return null;
  }

  @override
  Future<bool?> requestNotificationsPermission() async {
    requestNotificationsPermissionCalls += 1;
    return true;
  }

  @override
  Future<bool?> canScheduleExactNotifications() async {
    canScheduleExactNotificationsCalls += 1;
    return canScheduleExactNotificationsResult;
  }

  @override
  Future<bool?> requestExactAlarmsPermission() async {
    requestExactAlarmsPermissionCalls += 1;
    return true;
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    return const <PendingNotificationRequest>[];
  }

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    AndroidNotificationDetails? notificationDetails, {
    required AndroidScheduleMode scheduleMode,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    zonedScheduleCalls += 1;
    lastId = id;
    lastPayload = payload;
    lastNotificationDetails = notificationDetails;
  }
}

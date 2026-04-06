part of '../review_reminder_notification_scheduler_android_permissions_test.dart';

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
    this.initialPendingItems = const <ReviewReminderItem>[],
  }) : super(library: ffi.DynamicLibrary.process());

  final List<_WindowsScheduleOutcome> scheduleOutcomes;
  final List<ReviewReminderItem> initialPendingItems;

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
    for (final item in initialPendingItems) {
      final notificationId = FlutterLocalNotificationsReviewReminderScheduler
          .notificationIdForItem(
        item,
      );
      pendingIds.add(notificationId);
      payloadsById[notificationId] =
          FlutterLocalNotificationsReviewReminderScheduler.encodePayload(item);
    }
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
    this.scheduleError,
  }) : initializeResults = initializeResults ?? <bool>[initializeResult];

  final bool canScheduleExactNotificationsResult;
  final List<bool> initializeResults;
  final Object? scheduleError;

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
    if (scheduleError != null) {
      throw scheduleError!;
    }
    lastId = id;
    lastPayload = payload;
    lastNotificationDetails = notificationDetails;
  }
}

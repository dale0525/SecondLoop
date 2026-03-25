import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/actions/task_hub/task_hub_quick_actions.dart';
import '../../i18n/strings.g.dart';
import 'review_notification_plan.dart';

typedef NotificationTapHandler = void Function(
  ReviewReminderNotificationEvent event,
);

final class ReviewReminderNotificationEvent {
  const ReviewReminderNotificationEvent({
    required this.payload,
    this.actionId,
  });

  final String? payload;
  final String? actionId;
}

final class ReviewReminderNotificationPayload {
  const ReviewReminderNotificationPayload({
    required this.kind,
    required this.todoId,
  });

  final ReviewReminderItemKind kind;
  final String todoId;
}

final class _WindowsQuickActionLaunch {
  const _WindowsQuickActionLaunch({
    required this.actionId,
    required this.payload,
  });

  final String actionId;
  final String payload;
}

abstract interface class ReviewReminderNotificationScheduler {
  bool get supportsSystemNotifications;

  Future<void> ensureInitialized();

  Future<void> schedule(ReviewReminderPlan plan);

  Future<void> cancel();
}

final class FlutterLocalNotificationsReviewReminderScheduler
    implements ReviewReminderNotificationScheduler {
  FlutterLocalNotificationsReviewReminderScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationTapHandler? onTap,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _onTap = onTap;

  static const int notificationIdBase = 2026021100;
  static const String reviewQueuePayloadPrefix = 'review_queue:';
  static const String dueTodoPayloadPrefix = 'due_todo:';

  static const String quickActionTodayId = 'today';
  static const String quickActionTomorrowId = 'tomorrow';
  static const String quickActionStartId = 'start';
  static const String quickActionDoneId = 'done';
  static const String quickActionReopenId = 'reopen';
  static const String quickActionRedoId = 'redo';
  static const String quickActionDismissId = 'dismiss';

  static const String androidDoneActionId = quickActionDoneId;
  static const String androidDismissActionId = quickActionDismissId;

  static const String androidNotificationIcon = 'ic_stat_notify';

  static const String _androidChannelId = 'review_reminders_v1';
  static const String _androidChannelName = 'Review reminders';
  static const String _androidChannelDescription =
      'Reminders for pending todo reviews';

  static const String _windowsAppName = 'SecondLoop';
  static const String _windowsProdAppUserModelId = 'com.secondloop.secondloop';
  static const String _windowsDevAppUserModelId =
      'com.secondloop.secondloopdev';
  static const String _windowsAppUserModelId = String.fromEnvironment(
    'SECONDLOOP_APP_ID',
    defaultValue: _windowsProdAppUserModelId,
  );
  static const String _windowsGuid = 'd49b5b4a-0ea5-4e31-b5c9-945cc5405f59';
  static const String _windowsQuickActionPrefix = 'quick_action|';

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationTapHandler? _onTap;

  bool _initialized = false;
  bool _available = true;
  bool _timeZoneInitialized = false;

  @override
  bool get supportsSystemNotifications => _available;
  final Set<int> _managedNotificationIds = <int>{};

  @override
  Future<void> ensureInitialized() async {
    if (_initialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings(androidNotificationIcon),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      windows: WindowsInitializationSettings(
        appName: _windowsAppName,
        appUserModelId: _windowsAppUserModelId,
        guid: _windowsGuid,
      ),
    );

    try {
      await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (response) {
          _onTap?.call(eventFromResponse(response));
        },
      );

      await _cleanupLegacyWindowsArtifactsBestEffort();

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final launchResponse = launchDetails?.notificationResponse;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchResponse != null) {
        _onTap?.call(eventFromResponse(launchResponse));
      }
    } on MissingPluginException {
      _available = false;
      _initialized = true;
      return;
    }

    await _requestPermissionsBestEffort();
    _configureTimeZone();
    _initialized = true;
  }

  Future<void> _requestPermissionsBestEffort() async {
    try {
      final dynamic androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();

      final dynamic canScheduleExactNotifications =
          await androidImpl?.canScheduleExactNotifications();
      if (canScheduleExactNotifications == false) {
        await androidImpl?.requestExactAlarmsPermission();
      }
    } catch (_) {
      // ignore
    }

    try {
      final dynamic iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // ignore
    }

    try {
      final dynamic macosImpl = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      await macosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // ignore
    }
  }

  Future<void> _cleanupLegacyWindowsArtifactsBestEffort() async {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    try {
      final windowsImpl = _plugin.resolvePlatformSpecificImplementation<
          FlutterLocalNotificationsWindows>();
      if (windowsImpl == null) {
        return;
      }
      for (final legacyAumid
          in legacyWindowsAppUserModelIds(_windowsAppUserModelId)) {
        await windowsImpl.cleanupAumidArtifacts(legacyAumid);
      }
    } catch (_) {
      // ignore
    }
  }

  void _configureTimeZone() {
    if (_timeZoneInitialized) return;
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.UTC);
      _timeZoneInitialized = true;
    } catch (_) {
      // ignore
    }
  }

  @override
  Future<void> schedule(ReviewReminderPlan plan) async {
    await ensureInitialized();
    if (!_available) return;

    _configureTimeZone();
    if (!_timeZoneInitialized) return;

    await _cancelManagedNotifications();

    for (var i = 0; i < plan.items.length; i++) {
      final item = plan.items[i];
      final notificationId = notificationIdForItem(item);
      final scheduledAtUtc = DateTime.fromMillisecondsSinceEpoch(
        item.scheduleAtUtcMs,
        isUtc: true,
      );
      final scheduleAt = tz.TZDateTime.from(scheduledAtUtc, tz.local);
      final payload = encodePayload(item);
      final title = item.kind == ReviewReminderItemKind.reviewQueue
          ? t.actions.reviewQueue.title
          : t.actions.agenda.title;
      final details = notificationDetailsForItem(item);

      await _scheduleSingleNotification(
        notificationId: notificationId,
        title: title,
        body: item.todoTitle,
        scheduleAt: scheduleAt,
        details: details,
        payload: payload,
      );
    }
  }

  @visibleForTesting
  static int notificationIdForItem(ReviewReminderItem item) {
    final key = '${item.kind.name}:${item.todoId}';
    return notificationIdBase + (_stableHash(key) % 1000000);
  }

  @visibleForTesting
  static String encodePayload(ReviewReminderItem item) {
    final prefix = item.kind == ReviewReminderItemKind.reviewQueue
        ? reviewQueuePayloadPrefix
        : dueTodoPayloadPrefix;
    return '$prefix${item.todoId}';
  }

  @visibleForTesting
  static String notificationActionId(TaskHubQuickAction action) {
    return action.name;
  }

  @visibleForTesting
  static String encodeWindowsQuickActionArguments(
    String actionId,
    String payload,
  ) {
    return '$_windowsQuickActionPrefix$actionId|$payload';
  }

  @visibleForTesting
  static List<String> legacyWindowsAppUserModelIds(String currentAumid) {
    const knownAppIds = <String>{
      _windowsProdAppUserModelId,
      _windowsDevAppUserModelId,
    };
    return knownAppIds
        .where((aumid) => aumid.isNotEmpty && aumid != currentAumid)
        .toList(growable: false);
  }

  @visibleForTesting
  static ReviewReminderNotificationEvent eventFromResponse(
    NotificationResponse response,
  ) {
    final quickAction = _decodeWindowsQuickActionArguments(response.payload);
    if (quickAction != null) {
      return ReviewReminderNotificationEvent(
        payload: quickAction.payload,
        actionId: quickAction.actionId,
      );
    }
    return ReviewReminderNotificationEvent(
      payload: response.payload,
      actionId: response.actionId,
    );
  }

  @visibleForTesting
  static List<TaskHubQuickAction> notificationQuickActionsForItem(
    ReviewReminderItem item,
  ) {
    if (item.todoStatus == 'done') {
      return const <TaskHubQuickAction>[
        TaskHubQuickAction.reopen,
        TaskHubQuickAction.redo,
        TaskHubQuickAction.dismiss,
      ];
    }

    return <TaskHubQuickAction>[
      if (item.todoStatus == 'in_progress')
        TaskHubQuickAction.done
      else
        TaskHubQuickAction.start,
      TaskHubQuickAction.tomorrow,
      TaskHubQuickAction.today,
      if (item.todoStatus != 'in_progress') TaskHubQuickAction.done,
    ];
  }

  static TaskHubQuickAction? quickActionFromId(String? actionId) {
    if (actionId == null || actionId.isEmpty) {
      return null;
    }

    return switch (actionId) {
      quickActionTodayId => TaskHubQuickAction.today,
      quickActionTomorrowId => TaskHubQuickAction.tomorrow,
      quickActionStartId => TaskHubQuickAction.start,
      quickActionDoneId => TaskHubQuickAction.done,
      quickActionReopenId => TaskHubQuickAction.reopen,
      quickActionRedoId => TaskHubQuickAction.redo,
      quickActionDismissId => TaskHubQuickAction.dismiss,
      _ => null,
    };
  }

  static ReviewReminderNotificationPayload? decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload.startsWith(reviewQueuePayloadPrefix)) {
      final todoId = payload.substring(reviewQueuePayloadPrefix.length);
      if (todoId.isEmpty) return null;
      return ReviewReminderNotificationPayload(
        kind: ReviewReminderItemKind.reviewQueue,
        todoId: todoId,
      );
    }
    if (payload.startsWith(dueTodoPayloadPrefix)) {
      final todoId = payload.substring(dueTodoPayloadPrefix.length);
      if (todoId.isEmpty) return null;
      return ReviewReminderNotificationPayload(
        kind: ReviewReminderItemKind.dueTodo,
        todoId: todoId,
      );
    }
    return null;
  }

  @visibleForTesting
  static NotificationDetails notificationDetailsForItem(
    ReviewReminderItem item,
  ) {
    final payload = encodePayload(item);
    final quickActions = notificationQuickActionsForItem(item);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: _androidChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        icon: androidNotificationIcon,
        actions: <AndroidNotificationAction>[
          for (final action in quickActions)
            AndroidNotificationAction(
              notificationActionId(action),
              _labelForQuickAction(action),
              showsUserInterface: true,
            ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      windows: WindowsNotificationDetails(
        actions: <WindowsAction>[
          for (final action in quickActions)
            WindowsAction(
              content: _labelForQuickAction(action),
              arguments: encodeWindowsQuickActionArguments(
                notificationActionId(action),
                payload,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _scheduleSingleNotification({
    required int notificationId,
    required String title,
    required String body,
    required tz.TZDateTime scheduleAt,
    required NotificationDetails details,
    required String? payload,
  }) async {
    Future<void> scheduleWithMode(AndroidScheduleMode mode) {
      return _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        scheduleAt,
        details,
        androidScheduleMode: mode,
        payload: payload,
      );
    }

    try {
      await scheduleWithMode(AndroidScheduleMode.exactAllowWhileIdle);
      _managedNotificationIds.add(notificationId);
      return;
    } on MissingPluginException {
      _available = false;
      return;
    } on PlatformException {
      // Exact alarms can be blocked on newer Android versions.
    } catch (_) {
      return;
    }

    try {
      await scheduleWithMode(AndroidScheduleMode.inexactAllowWhileIdle);
      _managedNotificationIds.add(notificationId);
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  @override
  Future<void> cancel() async {
    await ensureInitialized();
    if (!_available) return;

    await _cancelManagedNotifications();
  }

  Future<void> _cancelManagedNotifications() async {
    final notificationIds = _managedNotificationIds.isEmpty
        ? await _discoverManagedNotificationIds()
        : _managedNotificationIds.toSet();

    if (notificationIds.isEmpty) {
      for (var i = 0; i < kReviewReminderMaxItems; i++) {
        await _cancelNotification(notificationIdBase + i);
      }
      return;
    }

    for (final notificationId in notificationIds) {
      await _cancelNotification(notificationId);
    }
    _managedNotificationIds.clear();
  }

  Future<Set<int>> _discoverManagedNotificationIds() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending
          .where((request) => decodePayload(request.payload) != null)
          .map((request) => request.id)
          .toSet();
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
    return <int>{};
  }

  Future<void> _cancelNotification(int notificationId) async {
    try {
      await _plugin.cancel(notificationId);
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  static _WindowsQuickActionLaunch? _decodeWindowsQuickActionArguments(
    String? rawPayload,
  ) {
    if (rawPayload == null ||
        rawPayload.isEmpty ||
        !rawPayload.startsWith(_windowsQuickActionPrefix)) {
      return null;
    }

    final remainder = rawPayload.substring(_windowsQuickActionPrefix.length);
    final separatorIndex = remainder.indexOf('|');
    if (separatorIndex <= 0 || separatorIndex >= remainder.length - 1) {
      return null;
    }

    final actionId = remainder.substring(0, separatorIndex);
    final payload = remainder.substring(separatorIndex + 1);
    if (payload.isEmpty) {
      return null;
    }

    return _WindowsQuickActionLaunch(
      actionId: actionId,
      payload: payload,
    );
  }

  static String _labelForQuickAction(TaskHubQuickAction action) {
    final taskHubActions = t.actions.taskHub.actions;
    return switch (action) {
      TaskHubQuickAction.today => taskHubActions.today,
      TaskHubQuickAction.tomorrow => taskHubActions.tomorrow,
      TaskHubQuickAction.start => taskHubActions.start,
      TaskHubQuickAction.done => taskHubActions.done,
      TaskHubQuickAction.reopen => taskHubActions.reopen,
      TaskHubQuickAction.redo => taskHubActions.redo,
      TaskHubQuickAction.dismiss => t.common.actions.delete,
      TaskHubQuickAction.increaseUrgency => taskHubActions.increaseUrgency,
      TaskHubQuickAction.decreaseUrgency => taskHubActions.decreaseUrgency,
      TaskHubQuickAction.increaseImportance =>
        taskHubActions.increaseImportance,
      TaskHubQuickAction.decreaseImportance =>
        taskHubActions.decreaseImportance,
    };
  }

  static int _stableHash(String input) {
    var value = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      value ^= codeUnit;
      value = (value * 0x01000193) & 0x7fffffff;
    }
    return value;
  }
}

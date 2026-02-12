import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../features/actions/review/review_queue_page.dart';
import '../backend/app_backend.dart';
import '../session/session_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';
import 'review_reminder_notification_coordinator.dart';
import 'review_reminder_notification_scheduler.dart';

typedef ReviewReminderSchedulerFactory = ReviewReminderNotificationScheduler
    Function(NotificationTapHandler onTap);

final class ReviewReminderNotificationsGate extends StatefulWidget {
  const ReviewReminderNotificationsGate({
    required this.child,
    required this.navigatorKey,
    this.schedulerFactory,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final ReviewReminderSchedulerFactory? schedulerFactory;

  @override
  State<ReviewReminderNotificationsGate> createState() =>
      _ReviewReminderNotificationsGateState();
}

final class _ReviewReminderNotificationsGateState
    extends State<ReviewReminderNotificationsGate> with WidgetsBindingObserver {
  static const _kRefreshDebounce = Duration(milliseconds: 500);

  late final ReviewReminderNotificationScheduler _scheduler =
      (widget.schedulerFactory ??
          (onTap) => FlutterLocalNotificationsReviewReminderScheduler(
                onTap: onTap,
              ))(_handleNotificationTap);

  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;
  ReviewReminderNotificationCoordinator? _coordinator;
  Timer? _refreshTimer;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _openingReviewQueueFromNotification = false;

  Object? _backendIdentity;
  Uint8List? _sessionKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachSyncEngine();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleRefresh();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (kIsWeb) {
      _detachSyncEngine();
      _coordinator = null;
      _refreshTimer?.cancel();
      return;
    }

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final shouldRebuildCoordinator = !identical(_backendIdentity, backend) ||
        !_bytesEqual(_sessionKey, sessionKey);

    if (shouldRebuildCoordinator) {
      _backendIdentity = backend;
      _sessionKey = Uint8List.fromList(sessionKey);
      _coordinator = ReviewReminderNotificationCoordinator(
        scheduler: _scheduler,
        readTodos: () => backend.listTodos(sessionKey),
      );
    }

    _attachSyncEngine(SyncEngineScope.maybeOf(context));
    _scheduleRefresh();
  }

  void _attachSyncEngine(SyncEngine? engine) {
    if (identical(engine, _syncEngine)) return;

    _detachSyncEngine();
    _syncEngine = engine;
    if (engine == null) return;

    void onSyncChange() => _scheduleRefresh();
    _syncListener = onSyncChange;
    engine.changes.addListener(onSyncChange);
  }

  void _detachSyncEngine() {
    final engine = _syncEngine;
    final listener = _syncListener;
    if (engine != null && listener != null) {
      engine.changes.removeListener(listener);
    }
    _syncEngine = null;
    _syncListener = null;
  }

  bool _bytesEqual(Uint8List? a, Uint8List b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_kRefreshDebounce, () {
      _refreshTimer = null;
      unawaited(_runRefresh());
    });
  }

  Future<void> _runRefresh() async {
    if (!mounted) return;
    final coordinator = _coordinator;
    if (coordinator == null) return;

    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }

    _refreshInFlight = true;
    try {
      await coordinator.refresh();
    } catch (_) {
      // Best-effort notifications should never break app flow.
    } finally {
      _refreshInFlight = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(_runRefresh());
      }
    }
  }

  void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (!payload.startsWith(
      FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix,
    )) {
      return;
    }

    unawaited(_openReviewQueueFromNotification());
  }

  Future<void> _openReviewQueueFromNotification() async {
    if (!mounted || _openingReviewQueueFromNotification) return;

    final navigator = widget.navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;

    _openingReviewQueueFromNotification = true;
    try {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const ReviewQueuePage()),
      );
    } finally {
      _openingReviewQueueFromNotification = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

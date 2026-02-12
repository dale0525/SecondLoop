import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../features/actions/review/review_queue_page.dart';
import '../../i18n/strings.g.dart';
import '../backend/app_backend.dart';
import '../session/session_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';
import 'review_notification_plan.dart';
import 'review_reminder_in_app_fallback_prefs.dart';
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
  Timer? _inAppFallbackTimer;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _openingReviewQueueFromNotification = false;

  Object? _backendIdentity;
  Uint8List? _sessionKey;

  bool _inAppFallbackEnabled = ReviewReminderInAppFallbackPrefs.defaultValue;
  bool _inAppFallbackVisible = false;
  String? _activeInAppFallbackSourceKey;
  String? _dismissedInAppFallbackSourceKey;
  int? _activeInAppFallbackPendingCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inAppFallbackEnabled = ReviewReminderInAppFallbackPrefs.value.value;
    ReviewReminderInAppFallbackPrefs.value
        .addListener(_handleInAppFallbackPrefChanged);
    unawaited(ReviewReminderInAppFallbackPrefs.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReviewReminderInAppFallbackPrefs.value
        .removeListener(_handleInAppFallbackPrefChanged);
    _detachSyncEngine();
    _refreshTimer?.cancel();
    _inAppFallbackTimer?.cancel();
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
      _dismissedInAppFallbackSourceKey = null;
    }

    _attachSyncEngine(SyncEngineScope.maybeOf(context));
    _syncInAppFallbackFromCurrentPlan();
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
      _syncInAppFallbackFromCurrentPlan();
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

  void _handleInAppFallbackPrefChanged() {
    final nextEnabled = ReviewReminderInAppFallbackPrefs.value.value;
    if (_inAppFallbackEnabled == nextEnabled) return;

    _inAppFallbackEnabled = nextEnabled;
    _dismissedInAppFallbackSourceKey = null;
    _syncInAppFallbackFromCurrentPlan();
    if (nextEnabled) _scheduleRefresh();
  }

  void _syncInAppFallbackFromCurrentPlan() {
    _inAppFallbackTimer?.cancel();
    _inAppFallbackTimer = null;

    if (!_inAppFallbackEnabled) {
      _hideInAppFallbackBanner();
      return;
    }

    final plan = _coordinator?.currentPlan;
    if (plan == null || plan.items.isEmpty || plan.pendingCount <= 0) {
      _dismissedInAppFallbackSourceKey = null;
      _hideInAppFallbackBanner();
      return;
    }

    final activeSourceKeys =
        plan.items.map(_inAppFallbackSourceKeyForItem).toSet();
    if (_dismissedInAppFallbackSourceKey != null &&
        !activeSourceKeys.contains(_dismissedInAppFallbackSourceKey)) {
      _dismissedInAppFallbackSourceKey = null;
    }

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    ReviewReminderItem? dueItem;
    ReviewReminderItem? nextItem;

    for (final item in plan.items) {
      final sourceKey = _inAppFallbackSourceKeyForItem(item);
      if (item.scheduleAtUtcMs <= nowUtcMs) {
        if (_dismissedInAppFallbackSourceKey == sourceKey) {
          continue;
        }
        dueItem = item;
        break;
      }

      if (_dismissedInAppFallbackSourceKey == sourceKey) {
        continue;
      }
      nextItem ??= item;
    }

    if (dueItem != null) {
      _showInAppFallbackBanner(
        pendingCount: plan.pendingCount,
        sourceKey: _inAppFallbackSourceKeyForItem(dueItem),
      );
      return;
    }

    _hideInAppFallbackBanner();
    if (nextItem == null) return;

    final targetSourceKey = _inAppFallbackSourceKeyForItem(nextItem);
    final delayMs = (nextItem.scheduleAtUtcMs - nowUtcMs).clamp(1, 1 << 31);
    _inAppFallbackTimer = Timer(Duration(milliseconds: delayMs), () {
      _inAppFallbackTimer = null;
      if (!mounted) return;
      final latestPlan = _coordinator?.currentPlan;
      if (latestPlan == null ||
          !_inAppFallbackEnabled ||
          _dismissedInAppFallbackSourceKey == targetSourceKey) {
        _syncInAppFallbackFromCurrentPlan();
        return;
      }

      final matches = latestPlan.items.any(
        (item) => _inAppFallbackSourceKeyForItem(item) == targetSourceKey,
      );
      if (!matches) {
        _syncInAppFallbackFromCurrentPlan();
        return;
      }

      _showInAppFallbackBanner(
        pendingCount: latestPlan.pendingCount,
        sourceKey: targetSourceKey,
      );
    });
  }

  String _inAppFallbackSourceKeyForItem(ReviewReminderItem item) {
    return '${item.kind.name}:${item.todoId}:${item.scheduleAtUtcMs}';
  }

  void _showInAppFallbackBanner({
    required int pendingCount,
    required String sourceKey,
  }) {
    if (!mounted) return;
    if (_inAppFallbackVisible &&
        _activeInAppFallbackSourceKey == sourceKey &&
        _activeInAppFallbackPendingCount == pendingCount) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final inAppFallbackT = context.t.actions.reviewQueue.inAppFallback;
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        key: const ValueKey('review_reminder_in_app_fallback_banner'),
        leading: const Icon(Icons.notifications_active_rounded),
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
        content: Text(
          inAppFallbackT.message(count: pendingCount),
        ),
        actions: [
          TextButton(
            key: const ValueKey('review_reminder_in_app_fallback_open'),
            onPressed: () {
              _hideInAppFallbackBanner();
              unawaited(_openReviewQueueFromNotification());
            },
            child: Text(inAppFallbackT.open),
          ),
          TextButton(
            key: const ValueKey('review_reminder_in_app_fallback_dismiss'),
            onPressed: () {
              _dismissedInAppFallbackSourceKey = sourceKey;
              _hideInAppFallbackBanner();
              _syncInAppFallbackFromCurrentPlan();
            },
            child: Text(inAppFallbackT.dismiss),
          ),
        ],
      ),
    );

    _inAppFallbackVisible = true;
    _activeInAppFallbackSourceKey = sourceKey;
    _activeInAppFallbackPendingCount = pendingCount;
  }

  void _hideInAppFallbackBanner() {
    if (!mounted) {
      _inAppFallbackVisible = false;
      _activeInAppFallbackSourceKey = null;
      _activeInAppFallbackPendingCount = null;
      return;
    }

    ScaffoldMessenger.maybeOf(context)?.hideCurrentMaterialBanner();
    _inAppFallbackVisible = false;
    _activeInAppFallbackSourceKey = null;
    _activeInAppFallbackPendingCount = null;
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

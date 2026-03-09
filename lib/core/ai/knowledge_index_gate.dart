import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../backend/app_backend.dart';
import '../backend/knowledge_backend.dart';
import '../session/session_scope.dart';

class KnowledgeIndexGate extends StatefulWidget {
  const KnowledgeIndexGate({required this.child, super.key});

  final Widget child;

  @override
  State<KnowledgeIndexGate> createState() => _KnowledgeIndexGateState();
}

class _KnowledgeIndexGateState extends State<KnowledgeIndexGate>
    with WidgetsBindingObserver {
  static const _idleInterval = Duration(seconds: 30);
  static const _drainInterval = Duration(milliseconds: 800);
  static const _failureInterval = Duration(seconds: 8);
  static const _batchLimit = 8;

  Timer? _timer;
  DateTime? _nextRunAt;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _schedule(_drainInterval);
        break;
      case AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
        _nextRunAt = null;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_shouldPauseInBackground()) {
          _timer?.cancel();
          _timer = null;
          _nextRunAt = null;
        }
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule(const Duration(seconds: 2));
  }

  bool _shouldPauseInBackground() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  void _schedule(Duration delay) {
    if (!mounted) return;

    final desired = DateTime.now().add(delay);
    final nextRunAt = _nextRunAt;
    if (nextRunAt != null && nextRunAt.isBefore(desired)) {
      return;
    }

    _timer?.cancel();
    _nextRunAt = desired;
    _timer = Timer(delay, () {
      _nextRunAt = null;
      unawaited(_runOnce());
    });
  }

  Future<void> _runOnce() async {
    if (_running || !mounted) return;

    final backend = AppBackendScope.maybeOf(context);
    final sessionScope = SessionScope.maybeOf(context);
    if (backend == null || sessionScope == null) return;

    final knowledgeBackend = maybeKnowledgeBackendFor(backend);
    if (knowledgeBackend == null) return;

    final key = Uint8List.fromList(sessionScope.sessionKey);
    _running = true;
    try {
      final status = await knowledgeBackend.getKnowledgeIndexStatus(key);
      if (status.rebuildRequired || status.status == 'empty') {
        await knowledgeBackend.requestKnowledgeRebuild(key);
      }

      final refreshedStatus =
          await knowledgeBackend.getKnowledgeIndexStatus(key);
      final shouldProcess = refreshedStatus.status == 'running' ||
          refreshedStatus.status == 'failed' ||
          refreshedStatus.status == 'requested' ||
          refreshedStatus.rebuildRequired ||
          refreshedStatus.status == 'empty';
      if (!shouldProcess) {
        _schedule(_idleInterval);
        return;
      }

      final processed = await knowledgeBackend.processPendingKnowledgeIndexJobs(
        key,
        limit: _batchLimit,
      );
      _schedule(processed > 0 ? _drainInterval : _idleInterval);
    } catch (error, stackTrace) {
      debugPrint('KnowledgeIndexGate: background tick failed: $error');
      debugPrint('$stackTrace');
      _schedule(_failureInterval);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

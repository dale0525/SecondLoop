import 'package:flutter/widgets.dart';

import 'sync_engine.dart';

@visibleForTesting
bool shouldApplySyncEngineGateWriteGateRehydration({
  required int requestVersion,
  required int latestVersion,
  required SyncBackendType? expectedBackendType,
  required SyncBackendType? activeBackendType,
  required String? expectedScopeId,
  required String? activeScopeId,
}) {
  return requestVersion == latestVersion &&
      expectedBackendType == activeBackendType &&
      expectedScopeId == activeScopeId;
}

final class SyncEngineGate extends StatelessWidget {
  const SyncEngineGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SyncEngineScope(
      engine: null,
      child: child,
    );
  }
}

final class SyncEngineScope extends InheritedWidget {
  const SyncEngineScope({
    required this.engine,
    required super.child,
    super.key,
  });

  final SyncEngine? engine;

  static SyncEngine? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SyncEngineScope>()
        ?.engine;
  }

  @override
  bool updateShouldNotify(SyncEngineScope oldWidget) =>
      engine != oldWidget.engine;
}

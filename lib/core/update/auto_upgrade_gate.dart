import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_update_service.dart';

class AutoUpgradeGate extends StatefulWidget {
  const AutoUpgradeGate({
    super.key,
    required this.child,
    this.updateService,
    this.enableInDebug = false,
  });

  final Widget child;
  final AppUpdateService? updateService;
  final bool enableInDebug;

  @override
  State<AutoUpgradeGate> createState() => _AutoUpgradeGateState();
}

class _AutoUpgradeGateState extends State<AutoUpgradeGate> {
  bool _checkScheduled = false;

  late final AppUpdateService _updateService;
  AppUpdateService? _ownedUpdateService;

  @override
  void initState() {
    super.initState();
    final provided = widget.updateService;
    if (provided != null) {
      _updateService = provided;
    } else {
      final owned = AppUpdateService();
      _updateService = owned;
      _ownedUpdateService = owned;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeAutoUpgrade());
    });
  }

  @override
  void dispose() {
    _ownedUpdateService?.dispose();
    super.dispose();
  }

  Future<void> _maybeAutoUpgrade() async {
    if (!kReleaseMode && !widget.enableInDebug) return;

    try {
      final result = await _updateService.checkForUpdates();
      final update = result.update;
      if (update == null || !update.canSeamlessInstall) {
        return;
      }
      await _updateService.installAndRestart(update);
    } catch (error, stackTrace) {
      debugPrint('auto_upgrade_skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

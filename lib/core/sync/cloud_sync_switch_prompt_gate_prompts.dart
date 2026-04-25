part of 'cloud_sync_switch_prompt_gate.dart';

extension _CloudSyncSwitchPromptGatePrompts on _CloudSyncSwitchPromptGateState {
  BuildContext? _resolvePromptContextOrReschedule() {
    final dialogContext = widget.navigatorKey?.currentContext;
    if (widget.navigatorKey != null && dialogContext == null) {
      _schedulePrompt();
      return null;
    }
    final effectiveContext = dialogContext ?? context;
    if (!effectiveContext.mounted) {
      _schedulePrompt();
      return null;
    }
    return effectiveContext;
  }

  Future<SyncSwitchDirection?> _promptSyncSwitchDirection() async {
    final directionContext = _resolvePromptContextOrReschedule();
    if (directionContext == null) {
      return null;
    }
    _dialogShowing = true;
    try {
      return await showSyncSwitchDirectionDialog(directionContext);
    } finally {
      _dialogShowing = false;
    }
  }

  Future<bool?> _promptSwitchToCloud() async {
    final switchContext = _resolvePromptContextOrReschedule();
    if (switchContext == null) return null;
    final t = switchContext.t;
    _dialogShowing = true;
    try {
      return await showDialog<bool>(
        context: switchContext,
        builder: (context) {
          return AlertDialog(
            title: Text(t.sync.cloudManagedVault.switchDialog.title),
            content: Text(t.sync.cloudManagedVault.switchDialog.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.sync.cloudManagedVault.switchDialog.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.sync.cloudManagedVault.switchDialog.confirm),
              ),
            ],
          );
        },
      );
    } finally {
      _dialogShowing = false;
    }
  }
}

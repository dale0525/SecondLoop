part of 'cloud_sync_switch_prompt_gate.dart';

extension _CloudSyncSwitchPromptGateKey on _CloudSyncSwitchPromptGateState {
  Future<void> _ensureManagedVaultSyncKey(String uid) async {
    final backendScope =
        context.getInheritedWidgetOfExactType<AppBackendScope>();
    if (backendScope == null) return;
    final backend = backendScope.backend;
    try {
      final syncKey = await SyncKeyManager.deriveManagedVaultSyncKey(
        vaultId: uid,
        deriveSyncKey: backend.deriveSyncKey,
      );
      await SyncKeyManager.save(
        write: _store.writeSyncKey,
        key: syncKey,
      );
    } catch (_) {
      // Best-effort self-heal for managed-vault key policy.
    }
  }
}

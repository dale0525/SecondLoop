part of 'cloud_sync_switch_prompt_gate.dart';

extension _CloudSyncSwitchPromptGateKey on _CloudSyncSwitchPromptGateState {
  bool get _usesCloudSessionModel =>
      context
          .getInheritedWidgetOfExactType<AppPlatformCapabilityScope>()
          ?.capabilities
          .usesCloudSessionModel ??
      false;

  Future<Uint8List> _resolveManagedVaultSyncKey({
    required String uid,
    required AppBackend backend,
  }) async {
    if (_usesCloudSessionModel) {
      return SyncKeyManager.loadOrCreate(
        read: _store.readSyncKey,
        write: _store.writeSyncKey,
      );
    }
    final syncKey = await SyncKeyManager.deriveManagedVaultSyncKey(
      vaultId: uid,
      deriveSyncKey: backend.deriveSyncKey,
    );
    await SyncKeyManager.save(
      write: _store.writeSyncKey,
      key: syncKey,
    );
    return syncKey;
  }

  Future<void> _ensureManagedVaultSyncKey(String uid) async {
    final backendScope =
        context.getInheritedWidgetOfExactType<AppBackendScope>();
    if (backendScope == null) return;
    final backend = backendScope.backend;
    try {
      await _resolveManagedVaultSyncKey(uid: uid, backend: backend);
    } catch (_) {
      // Best-effort self-heal for managed-vault key policy.
    }
  }
}

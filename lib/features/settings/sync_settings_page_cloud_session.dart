part of 'sync_settings_page.dart';

extension _SyncSettingsPageCloudSession on _SyncSettingsPageState {
  bool _bindCloudAuthController(CloudAuthController? controller) {
    if (identical(_cloudAuthController, controller)) {
      return false;
    }

    _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
    _cloudAuthController = controller;
    final listenable =
        controller is Listenable ? controller as Listenable : null;
    _cloudAuthListenable = listenable;
    _lastObservedCloudUid = controller?.uid?.trim();
    listenable?.addListener(_onCloudAuthChanged);
    return true;
  }

  void _onCloudAuthChanged() {
    final nextUid = _cloudAuthController?.uid?.trim();
    if (nextUid == _lastObservedCloudUid) {
      return;
    }
    _lastObservedCloudUid = nextUid;
    unawaited(_persistCloudSessionManagedVaultConfig(uidOverride: nextUid));
  }

  Future<void> _persistCloudSessionManagedVaultConfig({
    String? uidOverride,
  }) async {
    if (!_storeLoaded || !_usesCloudSessionModel) {
      return;
    }
    final cloudUid = (uidOverride ?? _cloudAuthController?.uid)?.trim();
    final backend = AppBackendScope.maybeOf(context);
    if (cloudUid == null || cloudUid.isEmpty) {
      await _store.writeAutoEnabled(false);
      if (mounted) {
        _setState(() => _autoEnabled = false);
      } else {
        _autoEnabled = false;
      }
      if (backend != null) {
        unawaited(BackgroundSync.refreshSchedule(
          backend: backend,
          configStore: _store,
        ));
      }
      return;
    }

    final savedRemoteRoot = (await _store.readRemoteRoot())?.trim();
    if (savedRemoteRoot != null &&
        savedRemoteRoot.isNotEmpty &&
        savedRemoteRoot != cloudUid) {
      return;
    }

    if (_remoteRootController.text != cloudUid) {
      _remoteRootController.text = cloudUid;
    }
    await _store.writePrimarySyncSettings(
      backendType: SyncBackendType.managedVault,
      remoteRoot: cloudUid,
    );
    if (backend != null) {
      unawaited(BackgroundSync.refreshSchedule(
        backend: backend,
        configStore: _store,
      ));
    }
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/backend/app_backend.dart';
import '../core/cloud/cloud_auth_access.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../core/session/session_scope.dart';
import '../core/sync/sync_config_store.dart';
import '../core/sync/sync_key_manager.dart';
import '../i18n/strings.g.dart';
import 'web_local_runtime_recovery.dart';
import 'web_local_runtime_recovery_base.dart';
import 'web_persistent_app_dir.dart';
import 'web_native_app_backend.dart';

typedef WebInitialSyncRunner = Future<void> Function(
  BuildContext context,
  AppBackend backend,
  Uint8List sessionKey,
);

class WebInitialSyncGate extends StatefulWidget {
  const WebInitialSyncGate({
    required this.authController,
    required this.managedVaultBaseUrl,
    required this.child,
    this.syncConfigStore,
    this.syncRunner,
    this.appDirResolver,
    this.localRuntimeRecovery,
    this.blockingTimeout = const Duration(seconds: 2),
    super.key,
  });

  final ObservableCloudAuthController authController;
  final String managedVaultBaseUrl;
  final Widget child;
  final SyncConfigStore? syncConfigStore;
  final WebInitialSyncRunner? syncRunner;
  final WebPersistentAppDirResolver? appDirResolver;
  final WebLocalRuntimeRecovery? localRuntimeRecovery;
  final Duration blockingTimeout;

  @override
  State<WebInitialSyncGate> createState() => _WebInitialSyncGateState();
}

class _WebInitialSyncGateState extends State<WebInitialSyncGate> {
  bool _bootstrapStarted = false;
  Timer? _blockingTimeoutTimer;
  Object? _bootstrapError;
  bool _allowPassThrough = false;
  bool _bootstrapCompleted = false;
  bool _didPassThroughBeforeBootstrapCompleted = false;
  int _childGeneration = 0;

  bool _canPassThroughBeforeBootstrapCompletes() {
    final backend = AppBackendScope.of(context);
    // Web-native shells share the same wasm SQLite runtime as the initial
    // managed-vault bootstrap pull. Letting the shell mount early can trigger
    // overlapping local DB access and trip memvfs re-entrancy panics.
    return backend is! WebNativeAppBackend;
  }

  bool _shouldResetLocalRuntimeAfterReadFailure(Object error) {
    final text = error.toString().trim().toLowerCase();
    if (text.isEmpty) return false;
    const resetSignals = <String>[
      'opfs',
      'memvfs',
      're-entr',
      'reentr',
      'sqlite',
      'sqlcipher',
      'database is malformed',
      'not a database',
      'corrupt',
    ];
    return resetSignals.any(text.contains);
  }

  @override
  void dispose() {
    _blockingTimeoutTimer?.cancel();
    _blockingTimeoutTimer = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;
    unawaited(_startBootstrap());
  }

  Future<void> _startBootstrap() async {
    _blockingTimeoutTimer?.cancel();
    _blockingTimeoutTimer = Timer(widget.blockingTimeout, () {
      if (!mounted || _bootstrapCompleted || _allowPassThrough) return;
      if (!_canPassThroughBeforeBootstrapCompletes()) return;
      setState(() {
        _allowPassThrough = true;
        _didPassThroughBeforeBootstrapCompleted = true;
      });
    });

    try {
      final runner = widget.syncRunner ?? _defaultSyncRunner;
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      await runner(context, backend, sessionKey);
      await _maybeRecoverLocalRuntime(backend, sessionKey);
      if (!mounted) return;
      _blockingTimeoutTimer?.cancel();
      setState(() {
        _bootstrapCompleted = true;
        _allowPassThrough = true;
        if (_didPassThroughBeforeBootstrapCompleted) {
          _childGeneration += 1;
        }
      });
    } catch (error) {
      if (!mounted) return;
      _blockingTimeoutTimer?.cancel();
      setState(() {
        _bootstrapCompleted = true;
        _bootstrapError = error;
      });
    }
  }

  Future<void> _defaultSyncRunner(
    BuildContext context,
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    final uid = widget.authController.uid?.trim() ?? '';
    final baseUrl = widget.managedVaultBaseUrl.trim();
    if (uid.isEmpty || baseUrl.isEmpty) return;
    final syncConfigStore = widget.syncConfigStore ?? SyncConfigStore();

    final idToken = await readCloudAuthIdToken(
      widget.authController,
      mode: CloudAuthAccessMode.interactive,
    );
    if (idToken == null || idToken.trim().isEmpty) {
      throw const _WebInitialSyncAuthTokenUnavailable();
    }

    final syncKey = await syncConfigStore.readSyncKey() ??
        await SyncKeyManager.deriveManagedVaultSyncKey(
          vaultId: uid,
          deriveSyncKey: backend.deriveSyncKey,
        );
    await syncConfigStore.writeSyncKey(syncKey);

    await backend.syncManagedVaultPull(
      sessionKey,
      syncKey,
      baseUrl: baseUrl,
      vaultId: uid,
      idToken: idToken,
    );
  }

  Future<void> _maybeRecoverLocalRuntime(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    if (backend is! WebNativeAppBackend) return;

    final uid = widget.authController.uid?.trim() ?? '';
    final baseUrl = widget.managedVaultBaseUrl.trim();
    if (uid.isEmpty || baseUrl.isEmpty) return;

    final resolver = widget.appDirResolver ?? OpfsWebPersistentAppDirResolver();
    final recovery =
        widget.localRuntimeRecovery ?? createDefaultWebLocalRuntimeRecovery();

    try {
      await backend.listConversations(sessionKey);
      recovery.clearResetAttempted(uid: uid);
      return;
    } catch (error) {
      if (!_shouldResetLocalRuntimeAfterReadFailure(error)) {
        rethrow;
      }
      if (recovery.hasAttemptedReset(uid: uid)) {
        rethrow;
      }
    }

    recovery.markResetAttempted(uid: uid);
    await resolver.bumpGeneration(uid: uid);
    await recovery.reloadPage();
    throw const _WebInitialSyncReloadRequested();
  }

  @override
  Widget build(BuildContext context) {
    final error = _bootstrapError;
    if (!_allowPassThrough && !_bootstrapCompleted) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (error is _WebInitialSyncReloadRequested) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null && !_allowPassThrough) {
      return Scaffold(
        body: Center(
          child: Text(
            context.t.errors.loadFailed(error: '$error'),
          ),
        ),
      );
    }
    return KeyedSubtree(
      key: ValueKey<int>(_childGeneration),
      child: widget.child,
    );
  }
}

final class _WebInitialSyncReloadRequested implements Exception {
  const _WebInitialSyncReloadRequested();
}

final class _WebInitialSyncAuthTokenUnavailable implements Exception {
  const _WebInitialSyncAuthTokenUnavailable();

  @override
  String toString() {
    return 'cloud_auth_token_unavailable';
  }
}

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
    super.key,
  });

  final ObservableCloudAuthController authController;
  final String managedVaultBaseUrl;
  final Widget child;
  final SyncConfigStore? syncConfigStore;
  final WebInitialSyncRunner? syncRunner;
  final WebPersistentAppDirResolver? appDirResolver;
  final WebLocalRuntimeRecovery? localRuntimeRecovery;

  @override
  State<WebInitialSyncGate> createState() => _WebInitialSyncGateState();
}

class _WebInitialSyncGateState extends State<WebInitialSyncGate> {
  Future<void>? _bootstrapFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bootstrapFuture ??= _bootstrap();
  }

  Future<void> _bootstrap() async {
    final runner = widget.syncRunner ?? _defaultSyncRunner;
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await runner(context, backend, sessionKey);
    await _maybeRecoverLocalRuntime(backend, sessionKey);
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
    if (idToken == null || idToken.trim().isEmpty) return;

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

    Object? localReadError;
    try {
      final conversations = await backend.listConversations(sessionKey);
      if (conversations.isNotEmpty) {
        recovery.clearResetAttempted(uid: uid);
        return;
      }
    } catch (error) {
      localReadError = error;
    }

    if (recovery.hasAttemptedReset(uid: uid)) {
      if (localReadError != null) {
        throw localReadError;
      }
      return;
    }

    recovery.markResetAttempted(uid: uid);
    await resolver.bumpGeneration(uid: uid);
    await recovery.reloadPage();
    throw const _WebInitialSyncReloadRequested();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.error is _WebInitialSyncReloadRequested) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                context.t.errors.loadFailed(error: '${snapshot.error}'),
              ),
            ),
          );
        }
        return widget.child;
      },
    );
  }
}

final class _WebInitialSyncReloadRequested implements Exception {
  const _WebInitialSyncReloadRequested();
}

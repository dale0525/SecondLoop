import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/cloud/cloud_auth_access.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_api_client.dart';
import '../../core/cloud/runtime_connection_store.dart';
import '../../core/cloud/runtime_manifest.dart';
import '../../core/cloud/runtime_note_client.dart';
import '../../core/cloud/runtime_profile.dart';
import '../../core/offline_edit/local_edit_store.dart';
import '../../core/offline_edit/local_edit_sync_service.dart';
import '../../i18n/strings.g.dart';
import 'note_editor_controller.dart';
import 'note_editor_page.dart';
import 'note_list_page.dart';

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({
    super.key,
    this.store,
    this.connectionStore,
    this.connectivity,
    this.noteHttpClient,
    this.nowMs,
  });

  final LocalEditStore? store;
  final RuntimeConnectionStore? connectionStore;
  final Connectivity? connectivity;
  final http.Client? noteHttpClient;
  final int Function()? nowMs;

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  LocalEditStore? _store;
  late final RuntimeConnectionStore _connectionStore;
  RuntimeNoteClient? _noteClient;
  Future<_NotesLoadResult>? _loadFuture;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  var _isOnline = true;

  @override
  void initState() {
    super.initState();
    _connectionStore = widget.connectionStore ?? RuntimeConnectionStore();
    _connectivitySub =
        (widget.connectivity ?? Connectivity()).onConnectivityChanged.listen(
      (results) {
        final online = !_isOffline(results);
        if (_isOnline == online) return;
        setState(() => _isOnline = online);
        if (online) {
          unawaited(_flushPendingAndReload());
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadFuture ??= _load();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    if (widget.store == null) {
      unawaited(_store?.close());
    }
    _disposeNoteClient();
    super.dispose();
  }

  Future<_NotesLoadResult> _load() async {
    final store = await _resolveStore();
    final target = await _resolveRuntimeTarget();
    final localEdits = await store.listAllEdits();
    var remoteNotes = const <RuntimeNote>[];
    if (target != null && _isOnline) {
      final client = _replaceNoteClient(target);
      remoteNotes = await client.listNotes(vaultId: target.vaultId, limit: 100);
    }
    return _NotesLoadResult(
      target: target,
      entries: mergeNoteListEntries(remoteNotes, localEdits),
    );
  }

  Future<LocalEditStore> _resolveStore() async {
    final existing = _store;
    if (existing != null) return existing;
    final store = widget.store ?? await LocalEditStore.openDefault();
    _store = store;
    return store;
  }

  Future<_NotesRuntimeTarget?> _resolveRuntimeTarget() async {
    final cloudScope = CloudAuthScope.maybeOf(context);
    final storedConnection = await _connectionStore.loadConnection();
    final storedTarget = await _targetFromStoredConnection(
      storedConnection,
      cloudScope,
    );
    if (storedTarget != null) return storedTarget;
    return _managedProTargetFromCloudScope(cloudScope);
  }

  Future<_NotesRuntimeTarget?> _targetFromStoredConnection(
    CloudRuntimeConnection? connection,
    CloudAuthScope? cloudScope,
  ) async {
    if (connection == null) return null;
    final vaultId = _vaultIdForConnection(connection, cloudScope);
    if (vaultId.isEmpty) return null;
    if (connection.profile.runtimeMode == CloudRuntimeMode.selfManaged) {
      return _NotesRuntimeTarget(
        vaultId: vaultId,
        loadConnection: () async => connection,
      );
    }

    final runtimeConnection = await _managedProConnectionWithToken(
      connection,
      cloudScope,
    );
    if (runtimeConnection == null) return null;
    return _NotesRuntimeTarget(
      vaultId: vaultId,
      loadConnection: () => _managedProConnectionWithToken(
        connection,
        cloudScope,
      ),
    );
  }

  RuntimeNoteClient _replaceNoteClient(_NotesRuntimeTarget target) {
    _disposeNoteClient();
    final client = RuntimeNoteClient(
      apiClient: RuntimeApiClient(
        connectionLoader: target.loadConnection,
        httpClient: widget.noteHttpClient,
      ),
    );
    _noteClient = client;
    return client;
  }

  void _disposeNoteClient() {
    final current = _noteClient;
    if (current == null) return;
    current.dispose();
    _noteClient = null;
  }

  Future<void> _flushPendingAndReload() async {
    final target = await _resolveRuntimeTarget();
    if (target != null) {
      final store = await _resolveStore();
      final client = _replaceNoteClient(target);
      final sync = LocalEditSyncService(
        store: store,
        vaultId: target.vaultId,
        nowMs: _nowMs,
        noteClient: client,
      );
      await sync.flushPending();
    }
    if (!mounted) return;
    setState(() {
      _loadFuture = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_NotesLoadResult>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(context.t.notes.title)),
            body: Center(
              child:
                  Text(context.t.errors.loadFailed(error: '${snapshot.error}')),
            ),
          );
        }
        final result = snapshot.data;
        final target = result?.target;
        return NoteListPage(
          entries: result?.entries ?? const <NoteListEntry>[],
          onDeleteNote: target == null || !_isOnline
              ? null
              : (entry) => _deleteNote(target, entry),
          onOpenNote: (entry) => unawaited(
            _openEditor(
              target,
              noteId: entry.id,
              baseRevision: entry.baseRevision,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditor(
    _NotesRuntimeTarget? target, {
    String? noteId,
    String? baseRevision,
  }) async {
    final store = await _resolveStore();
    final client = target == null ? null : _replaceNoteClient(target);
    final sync = LocalEditSyncService(
      store: store,
      vaultId: target?.vaultId ?? '',
      nowMs: _nowMs,
      saveNote: client?.saveNote ??
          ({
            required String vaultId,
            required String noteId,
            required String title,
            required String body,
            required String? baseRevision,
          }) async {
            throw StateError('runtime_note_client_unavailable');
          },
    );
    final controller = NoteEditorController(
      store: store,
      syncService: sync,
      vaultId: target?.vaultId ?? '',
      isOnline: () => target != null && _isOnline,
      nowMs: _nowMs,
      remoteId: noteId,
      baseRevision: baseRevision,
      noteClient: client,
    );
    await controller.load();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(context.t.notes.title)),
          body: NoteEditorPage(controller: controller),
        ),
      ),
    );
    controller.dispose();
    if (mounted) {
      setState(() {
        _loadFuture = _load();
      });
    }
  }

  Future<void> _deleteNote(
    _NotesRuntimeTarget target,
    NoteListEntry entry,
  ) async {
    final client = _replaceNoteClient(target);
    await client.deleteNote(
      vaultId: target.vaultId,
      noteId: entry.id,
      baseRevision: entry.baseRevision,
    );
    if (!mounted) return;
    setState(() {
      _loadFuture = _load();
    });
  }

  int _nowMs() {
    return (widget.nowMs ?? (() => DateTime.now().millisecondsSinceEpoch))();
  }
}

final class _NotesRuntimeTarget {
  const _NotesRuntimeTarget({
    required this.vaultId,
    required this.loadConnection,
  });

  final String vaultId;
  final Future<CloudRuntimeConnection?> Function() loadConnection;
}

final class _NotesLoadResult {
  const _NotesLoadResult({
    required this.target,
    required this.entries,
  });

  final _NotesRuntimeTarget? target;
  final List<NoteListEntry> entries;
}

bool _isOffline(List<ConnectivityResult> results) {
  return results.isEmpty ||
      results.every((result) => result == ConnectivityResult.none);
}

String _vaultIdForConnection(
  CloudRuntimeConnection connection,
  CloudAuthScope? cloudScope,
) {
  final profileVaultId = connection.profile.vaultId.trim();
  if (profileVaultId.isNotEmpty) return profileVaultId;
  final manifestVaultId = connection.manifest.vaultBinding?.trim() ?? '';
  if (manifestVaultId.isNotEmpty) return manifestVaultId;
  if (connection.profile.runtimeMode == CloudRuntimeMode.managedPro) {
    return cloudScope?.controller.uid?.trim() ?? '';
  }
  return '';
}

Future<_NotesRuntimeTarget?> _managedProTargetFromCloudScope(
  CloudAuthScope? cloudScope,
) async {
  final uid = cloudScope?.controller.uid?.trim() ?? '';
  final baseUrl = cloudScope?.gatewayConfig.baseUrl.trim() ?? '';
  if (uid.isEmpty || baseUrl.isEmpty) return null;
  final connection = await _managedProConnectionFromCloudScope(cloudScope);
  if (connection == null) return null;
  return _NotesRuntimeTarget(
    vaultId: uid,
    loadConnection: () => _managedProConnectionFromCloudScope(cloudScope),
  );
}

Future<CloudRuntimeConnection?> _managedProConnectionWithToken(
  CloudRuntimeConnection connection,
  CloudAuthScope? cloudScope,
) async {
  final baseUrl = connection.manifest.apiBaseUrl.trim().isNotEmpty
      ? connection.manifest.apiBaseUrl.trim()
      : connection.profile.apiBaseUrl.trim().isNotEmpty
          ? connection.profile.apiBaseUrl.trim()
          : cloudScope?.gatewayConfig.baseUrl.trim() ?? '';
  final token = connection.profile.authToken.trim().isNotEmpty
      ? connection.profile.authToken.trim()
      : (await readCloudAuthIdToken(
            cloudScope?.controller,
            mode: CloudAuthAccessMode.interactive,
          ))
              ?.trim() ??
          '';
  if (baseUrl.isEmpty || token.isEmpty) return null;
  return _copyRuntimeConnection(
    connection,
    apiBaseUrl: baseUrl,
    authToken: token,
  );
}

Future<CloudRuntimeConnection?> _managedProConnectionFromCloudScope(
  CloudAuthScope? cloudScope,
) async {
  final baseUrl = cloudScope?.gatewayConfig.baseUrl.trim() ?? '';
  final token = (await readCloudAuthIdToken(
        cloudScope?.controller,
        mode: CloudAuthAccessMode.interactive,
      ))
          ?.trim() ??
      '';
  if (baseUrl.isEmpty || token.isEmpty) return null;
  return CloudRuntimeConnection(
    profile: CloudRuntimeProfile(
      runtimeMode: CloudRuntimeMode.managedPro,
      apiBaseUrl: baseUrl,
      authMode: CloudRuntimeAuthMode.hostedSession,
      authToken: token,
      capabilityManifestId: 'managed-pro-runtime',
      manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    ),
    manifest: CloudRuntimeManifest(
      manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
      runtimeMode: CloudRuntimeMode.managedPro,
      apiBaseUrl: baseUrl,
      authMode: CloudRuntimeAuthMode.hostedSession,
      capabilities: CloudRuntimeRequiredCapabilities.all,
      skills: CloudRuntimeKnownSkills.all,
    ),
  );
}

CloudRuntimeConnection _copyRuntimeConnection(
  CloudRuntimeConnection connection, {
  required String apiBaseUrl,
  required String authToken,
}) {
  return CloudRuntimeConnection(
    profile: CloudRuntimeProfile(
      runtimeMode: connection.profile.runtimeMode,
      apiBaseUrl: apiBaseUrl,
      authMode: connection.profile.authMode,
      authToken: authToken,
      capabilityManifestId: connection.profile.capabilityManifestId,
      manifestVersion: connection.profile.manifestVersion,
      vaultId: connection.profile.vaultId,
    ),
    manifest: CloudRuntimeManifest(
      manifestVersion: connection.manifest.manifestVersion,
      runtimeMode: connection.manifest.runtimeMode,
      apiBaseUrl: apiBaseUrl,
      authMode: connection.manifest.authMode,
      capabilities: connection.manifest.capabilities,
      skills: connection.manifest.skills,
      vaultBinding: connection.manifest.vaultBinding,
      providerCostOwner: connection.manifest.providerCostOwner,
    ),
  );
}

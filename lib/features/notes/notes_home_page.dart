import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_access.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_note_client.dart';
import '../../core/offline_edit/local_edit_store.dart';
import '../../core/offline_edit/local_edit_sync_service.dart';
import '../../core/sync/sync_config_store.dart';
import '../../i18n/strings.g.dart';
import 'note_editor_controller.dart';
import 'note_editor_page.dart';
import 'note_list_page.dart';

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({
    super.key,
    this.store,
    this.configStore,
    this.connectivity,
    this.nowMs,
  });

  final LocalEditStore? store;
  final SyncConfigStore? configStore;
  final Connectivity? connectivity;
  final int Function()? nowMs;

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  LocalEditStore? _store;
  SyncConfigStore? _configStore;
  RuntimeNoteClient? _noteClient;
  Future<_NotesLoadResult>? _loadFuture;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  var _isOnline = true;

  @override
  void initState() {
    super.initState();
    _configStore = widget.configStore ?? SyncConfigStore();
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
    _noteClient?.dispose();
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
    final uid = cloudScope?.controller.uid?.trim() ?? '';
    final idToken = await readCloudAuthIdToken(
      cloudScope?.controller,
      mode: CloudAuthAccessMode.interactive,
    );
    final baseUrl = await _configStore?.resolveManagedVaultBaseUrl();
    if (uid.isEmpty || idToken == null || idToken.trim().isEmpty) {
      return null;
    }
    final normalizedBaseUrl = baseUrl?.trim() ?? '';
    if (normalizedBaseUrl.isEmpty) return null;
    return _NotesRuntimeTarget(
      managedVaultBaseUrl: normalizedBaseUrl,
      vaultId: uid,
      idToken: idToken,
    );
  }

  RuntimeNoteClient _replaceNoteClient(_NotesRuntimeTarget target) {
    final current = _noteClient;
    if (current != null) {
      current.dispose();
    }
    final client = RuntimeNoteClient(
      managedVaultBaseUrl: target.managedVaultBaseUrl,
      idToken: target.idToken,
    );
    _noteClient = client;
    return client;
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
    setState(() => _loadFuture = _load());
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
          onCreateNote: () => unawaited(_openEditor(target)),
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
      setState(() => _loadFuture = _load());
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
    setState(() => _loadFuture = _load());
  }

  int _nowMs() {
    return (widget.nowMs ?? (() => DateTime.now().millisecondsSinceEpoch))();
  }
}

final class _NotesRuntimeTarget {
  const _NotesRuntimeTarget({
    required this.managedVaultBaseUrl,
    required this.vaultId,
    required this.idToken,
  });

  final String managedVaultBaseUrl;
  final String vaultId;
  final String idToken;
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

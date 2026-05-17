import 'package:flutter/foundation.dart';

import '../../core/cloud/runtime_note_client.dart';
import '../../core/offline_edit/local_edit_models.dart';
import '../../core/offline_edit/local_edit_store.dart';
import '../../core/offline_edit/local_edit_sync_service.dart';

typedef RuntimeNoteLoader = Future<RuntimeNote> Function(String noteId);

enum NoteEditorStatus {
  clean,
  pending,
  saving,
  conflict,
  failed,
}

class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required LocalEditStore store,
    required LocalEditSyncService syncService,
    required String vaultId,
    required bool Function() isOnline,
    required int Function() nowMs,
    String? remoteId,
    String? baseRevision,
    RuntimeNoteClient? noteClient,
    RuntimeNoteLoader? loadNote,
  })  : _store = store,
        _syncService = syncService,
        _vaultId = vaultId,
        _isOnline = isOnline,
        _nowMs = nowMs,
        _remoteId = remoteId,
        _baseRevision = baseRevision,
        _loadNote = loadNote ??
            (noteClient == null
                ? null
                : ((noteId) => noteClient.fetchNote(
                      vaultId: vaultId,
                      noteId: noteId,
                    )));

  final LocalEditStore _store;
  final LocalEditSyncService _syncService;
  final String _vaultId;
  final bool Function() _isOnline;
  final int Function() _nowMs;
  final RuntimeNoteLoader? _loadNote;

  String? _localId;
  String? _remoteId;
  String? _baseRevision;
  String _title = '';
  String _body = '';
  NoteEditorStatus _status = NoteEditorStatus.clean;
  String? _conflictRemoteRevision;
  String? _conflictRemoteTitle;
  String? _conflictRemoteBody;

  String get vaultId => _vaultId;
  String? get localId => _localId;
  String? get remoteId => _remoteId;
  String? get baseRevision => _baseRevision;
  String get title => _title;
  String get body => _body;
  NoteEditorStatus get status => _status;
  String? get conflictRemoteRevision => _conflictRemoteRevision;
  String? get conflictRemoteTitle => _conflictRemoteTitle;
  String? get conflictRemoteBody => _conflictRemoteBody;

  Future<void> load() async {
    final remoteId = _remoteId;
    if (remoteId == null) {
      return;
    }

    final local = await _store.readByRemoteId(remoteId);
    if (local != null) {
      _applyLocalEdit(local);
      if (local.syncState != LocalEditSyncState.clean) {
        notifyListeners();
        return;
      }
    }

    final loader = _loadNote;
    if (_isOnline() && loader != null) {
      final remote = await loader(remoteId);
      _remoteId = remote.id;
      _baseRevision = remote.revision;
      _title = remote.title;
      _body = remote.body;
      _status = NoteEditorStatus.clean;
      _clearConflict();
    }
    notifyListeners();
  }

  Future<void> save({
    required String title,
    required String body,
  }) async {
    _title = title;
    _body = body;
    _status = _isOnline() ? NoteEditorStatus.saving : NoteEditorStatus.pending;
    notifyListeners();

    final draft = await _store.saveDraft(
      remoteId: _remoteId,
      title: title,
      body: body,
      baseRevision: _baseRevision,
      nowMs: _nowMs(),
    );
    _localId = draft.localId;
    _applyLocalEdit(draft);

    if (!_isOnline()) {
      _status = NoteEditorStatus.pending;
      notifyListeners();
      return;
    }

    await _syncService.flushPending();
    final saved = await _store.readByLocalId(draft.localId);
    if (saved == null) {
      _status = NoteEditorStatus.failed;
    } else {
      _applyLocalEdit(saved);
    }
    notifyListeners();
  }

  void _applyLocalEdit(LocalTextEdit edit) {
    _localId = edit.localId;
    _remoteId = edit.remoteId ?? _remoteId;
    _baseRevision = edit.baseRevision;
    _title = edit.title;
    _body = edit.body;
    _status = switch (edit.syncState) {
      LocalEditSyncState.clean => NoteEditorStatus.clean,
      LocalEditSyncState.pending => NoteEditorStatus.pending,
      LocalEditSyncState.syncing => NoteEditorStatus.saving,
      LocalEditSyncState.conflict => NoteEditorStatus.conflict,
      LocalEditSyncState.failed => NoteEditorStatus.failed,
    };
    _conflictRemoteRevision = edit.conflictRemoteRevision;
    _conflictRemoteTitle = edit.conflictRemoteTitle;
    _conflictRemoteBody = edit.conflictRemoteBody;
  }

  void _clearConflict() {
    _conflictRemoteRevision = null;
    _conflictRemoteTitle = null;
    _conflictRemoteBody = null;
  }
}

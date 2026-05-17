import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_edit_models.dart';

class LocalEditStore {
  LocalEditStore._({
    SharedPreferences? preferences,
    String? storageKey,
    List<LocalTextEdit>? initialEdits,
  })  : _preferences = preferences,
        _storageKey = storageKey,
        _edits = initialEdits ?? <LocalTextEdit>[];

  factory LocalEditStore.inMemory() {
    return LocalEditStore._();
  }

  factory LocalEditStore.persistent(String path) {
    final storageKey = 'memory:$path';
    return LocalEditStore._(
      storageKey: storageKey,
      initialEdits: List<LocalTextEdit>.of(
        _memoryPersistence[storageKey] ?? const <LocalTextEdit>[],
      ),
    );
  }

  static Future<LocalEditStore> openDefault() async {
    final preferences = await SharedPreferences.getInstance();
    return LocalEditStore._(
      preferences: preferences,
      storageKey: _defaultStorageKey,
      initialEdits: _decodeEdits(preferences.getString(_defaultStorageKey)),
    );
  }

  static const _defaultStorageKey = 'secondloop.offline_text_edits.v1';
  static final Map<String, List<LocalTextEdit>> _memoryPersistence = {};

  final SharedPreferences? _preferences;
  final String? _storageKey;
  final List<LocalTextEdit> _edits;
  final Random _random = _createRandom();
  var _localIdSequence = 0;

  Future<LocalTextEdit> saveDraft({
    String? remoteId,
    required String title,
    required String body,
    required String? baseRevision,
    required int nowMs,
  }) async {
    if (remoteId != null) {
      final existing = await readByRemoteId(remoteId);
      final edit = existing == null
          ? LocalTextEdit(
              localId: _createLocalId(nowMs),
              remoteId: remoteId,
              title: title,
              body: body,
              baseRevision: baseRevision,
              dirty: true,
              syncState: LocalEditSyncState.pending,
              updatedAtMs: nowMs,
              lastSyncedAtMs: null,
              conflictRemoteRevision: null,
              conflictRemoteTitle: null,
              conflictRemoteBody: null,
            )
          : LocalTextEdit(
              localId: existing.localId,
              remoteId: existing.remoteId,
              title: title,
              body: body,
              baseRevision: baseRevision,
              dirty: true,
              syncState: LocalEditSyncState.pending,
              updatedAtMs: nowMs,
              lastSyncedAtMs: existing.lastSyncedAtMs,
              conflictRemoteRevision: null,
              conflictRemoteTitle: null,
              conflictRemoteBody: null,
            );
      _upsert(edit);
      await _persist();
      return edit;
    }

    final edit = LocalTextEdit(
      localId: _createLocalId(nowMs),
      remoteId: null,
      title: title,
      body: body,
      baseRevision: baseRevision,
      dirty: true,
      syncState: LocalEditSyncState.pending,
      updatedAtMs: nowMs,
      lastSyncedAtMs: null,
      conflictRemoteRevision: null,
      conflictRemoteTitle: null,
      conflictRemoteBody: null,
    );
    _edits.add(edit);
    await _persist();
    return edit;
  }

  Future<List<LocalTextEdit>> listPendingEdits() async {
    return _sortedAscending(_edits
        .where((edit) => edit.syncState == LocalEditSyncState.pending)
        .toList());
  }

  Future<List<LocalTextEdit>> listRetryableEdits() async {
    return _sortedAscending(_edits
        .where((edit) =>
            edit.syncState == LocalEditSyncState.pending ||
            edit.syncState == LocalEditSyncState.failed)
        .toList());
  }

  Future<List<LocalTextEdit>> listAllEdits() async {
    final edits = List<LocalTextEdit>.of(_edits);
    edits.sort((a, b) {
      final updated = b.updatedAtMs.compareTo(a.updatedAtMs);
      if (updated != 0) {
        return updated;
      }
      return b.localId.compareTo(a.localId);
    });
    return edits;
  }

  Future<LocalTextEdit?> readByRemoteId(String remoteId) async {
    final matches = _edits.where((edit) => edit.remoteId == remoteId).toList();
    if (matches.isEmpty) {
      return null;
    }
    return _sortedDescending(matches).first;
  }

  Future<LocalTextEdit?> readByLocalId(String localId) async {
    for (final edit in _edits) {
      if (edit.localId == localId) {
        return edit;
      }
    }
    return null;
  }

  Future<void> markSynced({
    required String localId,
    required String remoteId,
    required String revision,
    required int nowMs,
  }) async {
    final existing = await readByLocalId(localId);
    if (existing == null) {
      return;
    }
    _upsert(
      _copyWith(
        existing,
        remoteId: remoteId,
        baseRevision: revision,
        dirty: false,
        syncState: LocalEditSyncState.clean,
        updatedAtMs: nowMs,
        lastSyncedAtMs: nowMs,
        clearConflict: true,
      ),
    );
    _removeRemoteDuplicates(remoteId, keepLocalId: localId);
    await _persist();
  }

  Future<void> markConflict({
    required String localId,
    required String remoteRevision,
    required String remoteTitle,
    required String remoteBody,
    required int nowMs,
  }) async {
    final existing = await readByLocalId(localId);
    if (existing == null) {
      return;
    }
    _upsert(
      _copyWith(
        existing,
        dirty: true,
        syncState: LocalEditSyncState.conflict,
        updatedAtMs: nowMs,
        conflictRemoteRevision: remoteRevision,
        conflictRemoteTitle: remoteTitle,
        conflictRemoteBody: remoteBody,
      ),
    );
    await _persist();
  }

  Future<void> markFailed({
    required String localId,
    required int nowMs,
  }) async {
    final existing = await readByLocalId(localId);
    if (existing == null) {
      return;
    }
    _upsert(
      _copyWith(
        existing,
        dirty: true,
        syncState: LocalEditSyncState.failed,
        updatedAtMs: nowMs,
      ),
    );
    await _persist();
  }

  Future<void> close() async {}

  void _upsert(LocalTextEdit edit) {
    final index = _edits.indexWhere((candidate) {
      return candidate.localId == edit.localId;
    });
    if (index >= 0) {
      _edits[index] = edit;
    } else {
      _edits.add(edit);
    }
  }

  void _removeRemoteDuplicates(String remoteId, {required String keepLocalId}) {
    _edits.removeWhere((edit) {
      return edit.remoteId == remoteId && edit.localId != keepLocalId;
    });
  }

  Future<void> _persist() async {
    final preferences = _preferences;
    final storageKey = _storageKey;
    if (storageKey == null) {
      return;
    }
    if (preferences == null) {
      _memoryPersistence[storageKey] = List<LocalTextEdit>.of(_edits);
      return;
    }
    await preferences.setString(
      storageKey,
      jsonEncode(_edits.map(_editToJson).toList(growable: false)),
    );
  }

  String _createLocalId(int nowMs) {
    final sequence = _localIdSequence++;
    return 'local-$nowMs-${_randomHex()}-$sequence';
  }

  String _randomHex() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i += 1) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static List<LocalTextEdit> _sortedAscending(List<LocalTextEdit> edits) {
    edits.sort((a, b) {
      final updated = a.updatedAtMs.compareTo(b.updatedAtMs);
      if (updated != 0) {
        return updated;
      }
      return a.localId.compareTo(b.localId);
    });
    return edits;
  }

  static List<LocalTextEdit> _sortedDescending(List<LocalTextEdit> edits) {
    edits.sort((a, b) {
      final updated = b.updatedAtMs.compareTo(a.updatedAtMs);
      if (updated != 0) {
        return updated;
      }
      return b.localId.compareTo(a.localId);
    });
    return edits;
  }

  static Random _createRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static List<LocalTextEdit> _decodeEdits(String? source) {
    if (source == null || source.isEmpty) {
      return <LocalTextEdit>[];
    }
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      return <LocalTextEdit>[];
    }
    return decoded
        .whereType<Map>()
        .map((json) => _editFromJson(Map<String, Object?>.from(json)))
        .toList(growable: true);
  }

  static Map<String, Object?> _editToJson(LocalTextEdit edit) {
    return {
      'local_id': edit.localId,
      'remote_id': edit.remoteId,
      'title': edit.title,
      'body': edit.body,
      'base_revision': edit.baseRevision,
      'dirty': edit.dirty,
      'sync_state': edit.syncState.name,
      'updated_at_ms': edit.updatedAtMs,
      'last_synced_at_ms': edit.lastSyncedAtMs,
      'conflict_remote_revision': edit.conflictRemoteRevision,
      'conflict_remote_title': edit.conflictRemoteTitle,
      'conflict_remote_body': edit.conflictRemoteBody,
    };
  }

  static LocalTextEdit _editFromJson(Map<String, Object?> json) {
    return LocalTextEdit(
      localId: json['local_id'] as String,
      remoteId: json['remote_id'] as String?,
      title: json['title'] as String,
      body: json['body'] as String,
      baseRevision: json['base_revision'] as String?,
      dirty: json['dirty'] as bool,
      syncState: _syncStateFromName(json['sync_state'] as String),
      updatedAtMs: json['updated_at_ms'] as int,
      lastSyncedAtMs: json['last_synced_at_ms'] as int?,
      conflictRemoteRevision: json['conflict_remote_revision'] as String?,
      conflictRemoteTitle: json['conflict_remote_title'] as String?,
      conflictRemoteBody: json['conflict_remote_body'] as String?,
    );
  }

  static LocalTextEdit _copyWith(
    LocalTextEdit edit, {
    String? remoteId,
    String? title,
    String? body,
    String? baseRevision,
    bool? dirty,
    LocalEditSyncState? syncState,
    int? updatedAtMs,
    int? lastSyncedAtMs,
    String? conflictRemoteRevision,
    String? conflictRemoteTitle,
    String? conflictRemoteBody,
    bool clearConflict = false,
  }) {
    return LocalTextEdit(
      localId: edit.localId,
      remoteId: remoteId ?? edit.remoteId,
      title: title ?? edit.title,
      body: body ?? edit.body,
      baseRevision: baseRevision ?? edit.baseRevision,
      dirty: dirty ?? edit.dirty,
      syncState: syncState ?? edit.syncState,
      updatedAtMs: updatedAtMs ?? edit.updatedAtMs,
      lastSyncedAtMs: lastSyncedAtMs ?? edit.lastSyncedAtMs,
      conflictRemoteRevision: clearConflict
          ? null
          : conflictRemoteRevision ?? edit.conflictRemoteRevision,
      conflictRemoteTitle: clearConflict
          ? null
          : conflictRemoteTitle ?? edit.conflictRemoteTitle,
      conflictRemoteBody:
          clearConflict ? null : conflictRemoteBody ?? edit.conflictRemoteBody,
    );
  }

  static LocalEditSyncState _syncStateFromName(String name) {
    return LocalEditSyncState.values.firstWhere(
      (state) => state.name == name,
    );
  }
}

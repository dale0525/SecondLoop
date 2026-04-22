import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_models.dart';

enum UpdateEventType {
  checkStarted,
  checkSucceeded,
  checkFailed,
  updateAvailable,
  manualFallback,
  stageStarted,
  stageSucceeded,
  stageFailed,
  installStarted,
  installDispatched,
  installFailed,
  pendingApplyStarted,
  pendingApplyDispatched,
  pendingApplySucceeded,
  pendingApplyFailed,
  stagedRestartStarted,
  stagedRestartDispatched,
  stagedRestartFailed,
}

enum UpdateFailureCategory {
  network,
  manifest,
  signature,
  integrity,
  runtimeUnavailable,
  unsupportedInstallLocation,
  permissions,
  installation,
  unknown,
}

class UpdateEventRecord {
  const UpdateEventRecord({
    required this.type,
    required this.timestampUtc,
    required this.platform,
    this.currentVersion,
    this.latestTag,
    this.installMode,
    this.message,
    this.failureCategory,
  });

  final UpdateEventType type;
  final DateTime timestampUtc;
  final AppUpdatePlatform platform;
  final String? currentVersion;
  final String? latestTag;
  final AppUpdateInstallMode? installMode;
  final String? message;
  final UpdateFailureCategory? failureCategory;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.name,
      'timestampUtc': timestampUtc.toUtc().toIso8601String(),
      'platform': platform.name,
      'currentVersion': currentVersion,
      'latestTag': latestTag,
      'installMode': installMode?.name,
      'message': message,
      'failureCategory': failureCategory?.name,
    };
  }

  static UpdateEventRecord? fromJson(Map<String, Object?> json) {
    final typeName = json['type'];
    final timestampValue = json['timestampUtc'];
    final platformName = json['platform'];
    if (typeName is! String ||
        timestampValue is! String ||
        platformName is! String) {
      return null;
    }

    final type =
        _firstWhereOrNull(UpdateEventType.values, (it) => it.name == typeName);
    final platform = _firstWhereOrNull(
      AppUpdatePlatform.values,
      (it) => it.name == platformName,
    );
    final timestamp = DateTime.tryParse(timestampValue)?.toUtc();
    if (type == null || platform == null || timestamp == null) {
      return null;
    }

    final installModeName = json['installMode'];
    final installMode = installModeName is String
        ? _firstWhereOrNull(
            AppUpdateInstallMode.values,
            (it) => it.name == installModeName,
          )
        : null;
    final failureCategoryName = json['failureCategory'];
    final failureCategory = failureCategoryName is String
        ? _firstWhereOrNull(
            UpdateFailureCategory.values,
            (it) => it.name == failureCategoryName,
          )
        : null;

    return UpdateEventRecord(
      type: type,
      timestampUtc: timestamp,
      platform: platform,
      currentVersion: json['currentVersion'] as String?,
      latestTag: json['latestTag'] as String?,
      installMode: installMode,
      message: json['message'] as String?,
      failureCategory: failureCategory,
    );
  }
}

abstract class UpdateEventLogger {
  Future<void> record(UpdateEventRecord record);

  Future<List<UpdateEventRecord>> readRecent();
}

final class SharedPrefsUpdateEventLogger implements UpdateEventLogger {
  static const prefsKey = 'update_event_log_v1';
  static const maxEntries = 20;
  static const retention = Duration(days: 7);

  SharedPrefsUpdateEventLogger({
    DateTime Function()? nowUtc,
  }) : _nowUtc = nowUtc ?? _systemNowUtc;

  final DateTime Function() _nowUtc;

  @override
  Future<void> record(UpdateEventRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = _decodeList(prefs.getString(prefsKey));
    existing.add(record);
    await _writePruned(prefs, existing);
  }

  @override
  Future<List<UpdateEventRecord>> readRecent() async {
    final prefs = await SharedPreferences.getInstance();
    return _prune(_decodeList(prefs.getString(prefsKey)));
  }

  List<UpdateEventRecord> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <UpdateEventRecord>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <UpdateEventRecord>[];
    final out = <UpdateEventRecord>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final mapped = <String, Object?>{};
      for (final entry in item.entries) {
        if (entry.key is String) {
          mapped[entry.key as String] = entry.value;
        }
      }
      final record = UpdateEventRecord.fromJson(mapped);
      if (record != null) {
        out.add(record);
      }
    }
    return out;
  }

  List<UpdateEventRecord> _prune(List<UpdateEventRecord> entries) {
    if (entries.isEmpty) return <UpdateEventRecord>[];
    final cutoff = _nowUtc().subtract(retention);
    final recentOnly = entries
        .where((entry) => !entry.timestampUtc.isBefore(cutoff))
        .toList(growable: false);
    if (recentOnly.length <= maxEntries) {
      return recentOnly;
    }
    return recentOnly.sublist(recentOnly.length - maxEntries);
  }

  Future<void> _writePruned(
    SharedPreferences prefs,
    List<UpdateEventRecord> entries,
  ) async {
    final pruned = _prune(entries);
    await prefs.setString(
      prefsKey,
      jsonEncode(
        pruned.map((entry) => entry.toJson()).toList(growable: false),
      ),
    );
  }

  static DateTime _systemNowUtc() => DateTime.now().toUtc();

  @visibleForTesting
  static Future<void> resetForTests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}

UpdateFailureCategory classifyUpdateFailure(Object error) {
  final raw = error.toString().toLowerCase();
  if (raw.contains('http_') ||
      raw.contains('download_failed') ||
      raw.contains('signature_fetch_failed') ||
      raw.contains('socket') ||
      raw.contains('connection')) {
    return UpdateFailureCategory.network;
  }
  if (raw.contains('invalid_release_tag') ||
      raw.contains('invalid_release_payload') ||
      raw.contains('invalid_json') ||
      raw.contains('missing_release') ||
      raw.contains('missing_update_asset') ||
      raw.contains('missing_release_notes_asset') ||
      raw.contains('invalid_release_notes_payload')) {
    return UpdateFailureCategory.manifest;
  }
  if (raw.contains('signature') || raw.contains('ed25519')) {
    return UpdateFailureCategory.signature;
  }
  if (raw.contains('sha256') || raw.contains('integrity')) {
    return UpdateFailureCategory.integrity;
  }
  if (raw.contains('velopack_unavailable') ||
      raw.contains('staged_update_not_supported') ||
      raw.contains('staged_update_restart_not_supported') ||
      raw.contains('seamless_update_not_supported') ||
      raw.contains('no_pending_update')) {
    return UpdateFailureCategory.runtimeUnavailable;
  }
  if (raw.contains('unsupported_install_location')) {
    return UpdateFailureCategory.unsupportedInstallLocation;
  }
  if (raw.contains('permission') || raw.contains('access denied')) {
    return UpdateFailureCategory.permissions;
  }
  if (raw.contains('apply_failed') ||
      raw.contains('install_failed') ||
      raw.contains('restart_failed') ||
      raw.contains('install_archive') ||
      raw.contains('chmod_failed') ||
      raw.contains('missing_app_bundle')) {
    return UpdateFailureCategory.installation;
  }
  return UpdateFailureCategory.unknown;
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) {
      return value;
    }
  }
  return null;
}

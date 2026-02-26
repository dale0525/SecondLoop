import 'dart:convert';
import 'dart:typed_data';

import 'sync_key_manager.dart';
import 'sync_secret_store.dart';

final class SyncConfigMigrator {
  SyncConfigMigrator({required SyncSecretStore secretStore})
      : _secretStore = secretStore;

  static const legacyPrefsBlobKey = 'sync_config_plain_json_v1';
  static const publicPrefsBlobKey = 'sync_config_public_json_v2';
  static const secretStoreVersionPrefsKey = 'sync_secret_store_version';
  static const secretStoreVersion = 1;
  static const webdavPasswordKey = 'sync_webdav_password';
  static const syncKeyB64Key = 'sync_webdav_sync_key_b64';

  final SyncSecretStore _secretStore;

  Map<String, String> decodeRawConfigMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, String>{};

      final result = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value is String) {
          result[key] = value;
          continue;
        }
        if (value == null) continue;
        result[key] = value.toString();
      }
      return result;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<SyncConfigPublicMigrationResult>
      migrateSensitiveFieldsFromPublicConfig(
    Map<String, String> publicConfig,
  ) async {
    final migrated = Map<String, String>.from(publicConfig);
    var movedSensitiveFields = false;

    final legacyPassword = migrated[webdavPasswordKey];
    if (legacyPassword != null && legacyPassword.isNotEmpty) {
      await _secretStore.writeWebdavPassword(legacyPassword);
      movedSensitiveFields = true;
    }
    if (migrated.remove(webdavPasswordKey) != null) {
      movedSensitiveFields = true;
    }

    final legacySyncKeyB64 = migrated[syncKeyB64Key];
    if (legacySyncKeyB64 != null && legacySyncKeyB64.isNotEmpty) {
      try {
        final decoded = base64Decode(legacySyncKeyB64);
        if (decoded.length == 32) {
          final key = Uint8List.fromList(decoded);
          await _secretStore.writeSyncKey(key);
          SyncKeyManager.cacheSyncKey(key);
          movedSensitiveFields = true;
        }
      } catch (_) {}
    }
    if (migrated.remove(syncKeyB64Key) != null) {
      movedSensitiveFields = true;
    }

    return SyncConfigPublicMigrationResult(
      publicConfig: migrated,
      movedSensitiveFields: movedSensitiveFields,
    );
  }
}

final class SyncConfigPublicMigrationResult {
  const SyncConfigPublicMigrationResult({
    required this.publicConfig,
    required this.movedSensitiveFields,
  });

  final Map<String, String> publicConfig;
  final bool movedSensitiveFields;
}

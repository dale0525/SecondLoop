import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'runtime_manifest.dart';
import 'runtime_profile.dart';

@immutable
class CloudRuntimeConnection {
  const CloudRuntimeConnection({
    required this.profile,
    required this.manifest,
  });

  final CloudRuntimeProfile profile;
  final CloudRuntimeManifest manifest;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profile': profile.toJson(),
      'manifest': manifest.toJson(),
    };
  }

  factory CloudRuntimeConnection.fromJson(Map<String, dynamic> json) {
    return CloudRuntimeConnection(
      profile: CloudRuntimeProfile.fromJson(
        Map<String, dynamic>.from(json['profile'] as Map? ?? const {}),
      ),
      manifest: CloudRuntimeManifest.fromJson(
        Map<String, dynamic>.from(json['manifest'] as Map? ?? const {}),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CloudRuntimeConnection &&
        other.profile == profile &&
        other.manifest == manifest;
  }

  @override
  int get hashCode => Object.hash(profile, manifest);
}

final class RuntimeConnectionStore {
  static const connectionPrefsKey = 'cloud_runtime_connection_v1';
  static const supportedManifestVersion = 1;
  static CloudRuntimeConnection? _cachedConnection;
  static var _cachePrimed = false;

  static CloudRuntimeConnection? get cachedConnection => _cachedConnection;
  static bool get cachePrimed => _cachePrimed;

  @visibleForTesting
  static void resetCacheForTests() {
    _cachedConnection = null;
    _cachePrimed = false;
  }

  Future<void> saveConnection(CloudRuntimeConnection connection) async {
    _validateManifestVersion(connection.profile.manifestVersion);
    _validateManifestVersion(connection.manifest.manifestVersion);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(connectionPrefsKey, jsonEncode(connection.toJson()));
    _cachedConnection = connection;
    _cachePrimed = true;
  }

  Future<CloudRuntimeConnection?> loadConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(connectionPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      _cachedConnection = null;
      _cachePrimed = true;
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('invalid_cloud_runtime_connection');
    }
    final connection = _migrateLegacyConnection(
      CloudRuntimeConnection.fromJson(decoded),
    );
    _validateManifestVersion(connection.profile.manifestVersion);
    _validateManifestVersion(connection.manifest.manifestVersion);
    if (connection.toJson().toString() != decoded.toString()) {
      await prefs.setString(
          connectionPrefsKey, jsonEncode(connection.toJson()));
    }
    _cachedConnection = connection;
    _cachePrimed = true;
    return connection;
  }

  Future<void> clearConnection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(connectionPrefsKey);
    _cachedConnection = null;
    _cachePrimed = true;
  }

  void _validateManifestVersion(int manifestVersion) {
    if (manifestVersion != supportedManifestVersion) {
      throw UnsupportedError('unsupported manifest_version: $manifestVersion');
    }
  }
}

CloudRuntimeConnection _migrateLegacyConnection(
  CloudRuntimeConnection connection,
) {
  if (connection.profile.runtimeMode != CloudRuntimeMode.selfManaged ||
      connection.profile.vaultId.trim().isNotEmpty) {
    return connection;
  }
  final vaultId = connection.manifest.vaultBinding?.trim() ?? '';
  if (vaultId.isEmpty) return connection;
  return CloudRuntimeConnection(
    profile: CloudRuntimeProfile(
      runtimeMode: connection.profile.runtimeMode,
      apiBaseUrl: connection.profile.apiBaseUrl,
      authMode: connection.profile.authMode,
      authToken: connection.profile.authToken,
      capabilityManifestId: connection.profile.capabilityManifestId,
      manifestVersion: connection.profile.manifestVersion,
      vaultId: vaultId,
    ),
    manifest: connection.manifest,
  );
}

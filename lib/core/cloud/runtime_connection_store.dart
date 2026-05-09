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

  Future<void> saveConnection(CloudRuntimeConnection connection) async {
    _validateManifestVersion(connection.profile.manifestVersion);
    _validateManifestVersion(connection.manifest.manifestVersion);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(connectionPrefsKey, jsonEncode(connection.toJson()));
  }

  Future<CloudRuntimeConnection?> loadConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(connectionPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('invalid_cloud_runtime_connection');
    }
    final connection = CloudRuntimeConnection.fromJson(decoded);
    _validateManifestVersion(connection.profile.manifestVersion);
    _validateManifestVersion(connection.manifest.manifestVersion);
    return connection;
  }

  Future<void> clearConnection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(connectionPrefsKey);
  }

  void _validateManifestVersion(int manifestVersion) {
    if (manifestVersion != supportedManifestVersion) {
      throw UnsupportedError('unsupported manifest_version: $manifestVersion');
    }
  }
}

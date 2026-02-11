import 'package:shared_preferences/shared_preferences.dart';

enum MediaSourcePreference {
  auto,
  cloud,
  byok,
  local,
}

enum MediaSourceRouteKind {
  cloudGateway,
  byok,
  local,
}

final class MediaSourcePrefs {
  static const prefsKey = 'media_source_preference_v1';

  static Future<MediaSourcePreference> read() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(prefsKey));
  }

  static Future<void> write(MediaSourcePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _encode(preference);
    if (raw == null) {
      await prefs.remove(prefsKey);
      return;
    }
    await prefs.setString(prefsKey, raw);
  }

  static MediaSourcePreference _decode(String? raw) {
    return switch (raw?.trim() ?? '') {
      'cloud' => MediaSourcePreference.cloud,
      'byok' => MediaSourcePreference.byok,
      'local' => MediaSourcePreference.local,
      _ => MediaSourcePreference.auto,
    };
  }

  static String? _encode(MediaSourcePreference preference) {
    return switch (preference) {
      MediaSourcePreference.auto => null,
      MediaSourcePreference.cloud => 'cloud',
      MediaSourcePreference.byok => 'byok',
      MediaSourcePreference.local => 'local',
    };
  }
}

MediaSourceRouteKind resolveMediaSourceRoute(
  MediaSourcePreference preference, {
  required bool cloudAvailable,
  required bool hasByokProfile,
  bool hasLocalCapability = true,
}) {
  final canUseCloud = cloudAvailable;
  final canUseByok = hasByokProfile;
  final canUseLocal = hasLocalCapability;

  MediaSourceRouteKind byPriority({
    required bool preferCloud,
    required bool preferByok,
    required bool preferLocal,
  }) {
    if (preferCloud && canUseCloud) {
      return MediaSourceRouteKind.cloudGateway;
    }
    if (preferByok && canUseByok) {
      return MediaSourceRouteKind.byok;
    }
    if (preferLocal && canUseLocal) {
      return MediaSourceRouteKind.local;
    }
    if (canUseByok) return MediaSourceRouteKind.byok;
    if (canUseCloud) return MediaSourceRouteKind.cloudGateway;
    return MediaSourceRouteKind.local;
  }

  return switch (preference) {
    MediaSourcePreference.auto => byPriority(
        preferCloud: true,
        preferByok: true,
        preferLocal: true,
      ),
    MediaSourcePreference.cloud => byPriority(
        preferCloud: true,
        preferByok: true,
        preferLocal: true,
      ),
    MediaSourcePreference.byok => byPriority(
        preferCloud: false,
        preferByok: true,
        preferLocal: true,
      ),
    MediaSourcePreference.local => byPriority(
        preferCloud: false,
        preferByok: false,
        preferLocal: true,
      ),
  };
}

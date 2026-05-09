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
  needsSetup,
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
      'local' => MediaSourcePreference.auto,
      _ => MediaSourcePreference.auto,
    };
  }

  static String? _encode(MediaSourcePreference preference) {
    return switch (preference) {
      MediaSourcePreference.auto => null,
      MediaSourcePreference.cloud => 'cloud',
      MediaSourcePreference.byok => 'byok',
      MediaSourcePreference.local => null,
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

  final preferredOrder = mediaSourceFallbackOrder(preference);
  for (final route in preferredOrder) {
    switch (route) {
      case MediaSourceRouteKind.cloudGateway:
        if (canUseCloud) return MediaSourceRouteKind.cloudGateway;
        break;
      case MediaSourceRouteKind.byok:
        if (canUseByok) return MediaSourceRouteKind.byok;
        break;
      case MediaSourceRouteKind.needsSetup:
        return MediaSourceRouteKind.needsSetup;
      case MediaSourceRouteKind.local:
        break;
    }
  }

  return MediaSourceRouteKind.needsSetup;
}

List<MediaSourceRouteKind> mediaSourceFallbackOrder(
  MediaSourcePreference preference,
) {
  return switch (preference) {
    MediaSourcePreference.auto ||
    MediaSourcePreference.cloud =>
      const <MediaSourceRouteKind>[
        MediaSourceRouteKind.cloudGateway,
        MediaSourceRouteKind.byok,
      ],
    MediaSourcePreference.byok => const <MediaSourceRouteKind>[
        MediaSourceRouteKind.byok,
      ],
    MediaSourcePreference.local => const <MediaSourceRouteKind>[
        MediaSourceRouteKind.cloudGateway,
        MediaSourceRouteKind.byok,
      ],
  };
}

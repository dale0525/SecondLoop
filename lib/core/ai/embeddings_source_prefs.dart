import 'package:shared_preferences/shared_preferences.dart';

enum EmbeddingsSourcePreference {
  auto,
  cloud,
  byok,
  local,
}

enum EmbeddingsSourceRouteKind {
  cloudGateway,
  byok,
  local,
}

final class EmbeddingsSourcePrefs {
  static const prefsKey = 'embeddings_source_preference_v1';

  static Future<EmbeddingsSourcePreference> read() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(prefsKey));
  }

  static Future<void> write(EmbeddingsSourcePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _encode(preference);
    if (raw == null) {
      await prefs.remove(prefsKey);
      return;
    }
    await prefs.setString(prefsKey, raw);
  }

  static EmbeddingsSourcePreference _decode(String? raw) {
    return switch (raw?.trim() ?? '') {
      'cloud' => EmbeddingsSourcePreference.cloud,
      'byok' => EmbeddingsSourcePreference.byok,
      'local' => EmbeddingsSourcePreference.local,
      _ => EmbeddingsSourcePreference.auto,
    };
  }

  static String? _encode(EmbeddingsSourcePreference preference) {
    return switch (preference) {
      EmbeddingsSourcePreference.auto => null,
      EmbeddingsSourcePreference.cloud => 'cloud',
      EmbeddingsSourcePreference.byok => 'byok',
      EmbeddingsSourcePreference.local => 'local',
    };
  }
}

EmbeddingsSourceRouteKind resolveEmbeddingsSourceRoute(
  EmbeddingsSourcePreference preference, {
  required bool cloudEmbeddingsSelected,
  required bool cloudAvailable,
  required bool hasByokProfile,
  bool hasLocalCapability = true,
}) {
  final canUseCloud = cloudEmbeddingsSelected && cloudAvailable;
  final canUseByok = hasByokProfile;
  final canUseLocal = hasLocalCapability;

  final preferredOrder = embeddingsSourceFallbackOrder(preference);
  for (final route in preferredOrder) {
    switch (route) {
      case EmbeddingsSourceRouteKind.cloudGateway:
        if (canUseCloud) return EmbeddingsSourceRouteKind.cloudGateway;
        break;
      case EmbeddingsSourceRouteKind.byok:
        if (canUseByok) return EmbeddingsSourceRouteKind.byok;
        break;
      case EmbeddingsSourceRouteKind.local:
        if (canUseLocal) return EmbeddingsSourceRouteKind.local;
        break;
    }
  }

  return EmbeddingsSourceRouteKind.local;
}

List<EmbeddingsSourceRouteKind> embeddingsSourceFallbackOrder(
  EmbeddingsSourcePreference preference,
) {
  return switch (preference) {
    EmbeddingsSourcePreference.auto ||
    EmbeddingsSourcePreference.cloud =>
      const <EmbeddingsSourceRouteKind>[
        EmbeddingsSourceRouteKind.cloudGateway,
        EmbeddingsSourceRouteKind.byok,
        EmbeddingsSourceRouteKind.local,
      ],
    EmbeddingsSourcePreference.byok => const <EmbeddingsSourceRouteKind>[
        EmbeddingsSourceRouteKind.byok,
        EmbeddingsSourceRouteKind.local,
      ],
    EmbeddingsSourcePreference.local => const <EmbeddingsSourceRouteKind>[
        EmbeddingsSourceRouteKind.local,
      ],
  };
}

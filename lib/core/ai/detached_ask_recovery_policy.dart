Duration detachedAskRecoveryPollDelay({
  required int nowMs,
  required int? createdAtMs,
}) {
  final ageMs = createdAtMs == null ? 0 : nowMs - createdAtMs;
  final normalizedAgeMs = ageMs < 0 ? 0 : ageMs;

  if (normalizedAgeMs >= 10 * 60 * 1000) {
    return const Duration(seconds: 15);
  }
  if (normalizedAgeMs >= 2 * 60 * 1000) {
    return const Duration(seconds: 8);
  }
  return const Duration(seconds: 3);
}

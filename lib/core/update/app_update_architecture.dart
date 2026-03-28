String normalizeArchitectureLabel(String? value) {
  final normalized = value?.trim().toLowerCase() ?? 'unknown';
  if (normalized.contains('aarch64') || normalized.contains('arm64')) {
    return 'arm64';
  }
  if (normalized.contains('x86_64') ||
      normalized.contains('amd64') ||
      normalized.contains('x64')) {
    return 'x64';
  }
  return normalized;
}

List<String> preferredMacosManifestKeysForArchitecture(String architecture) {
  final normalized = normalizeArchitectureLabel(architecture);
  if (normalized == 'arm64') {
    return const ['macos-universal', 'darwin-aarch64'];
  }
  if (normalized == 'x64') {
    return const ['macos-universal', 'darwin-x86_64'];
  }
  return const ['macos-universal', 'darwin-aarch64', 'darwin-x86_64'];
}

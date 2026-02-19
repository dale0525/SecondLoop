const List<String> kSystemDomainTagKeys = <String>[
  'work',
  'personal',
  'family',
  'health',
  'finance',
  'study',
  'travel',
  'social',
  'home',
  'hobby',
];

bool isSystemDomainTagKey(String systemKey) {
  return kSystemDomainTagKeys.contains(systemKey.trim());
}

String systemDomainTagId(String systemKey) {
  final normalized = systemKey.trim();
  return 'system.tag.$normalized';
}

String? systemDomainKeyFromTagId(String tagId) {
  final normalized = tagId.trim();
  if (!normalized.startsWith('system.tag.')) return null;

  final key = normalized.substring('system.tag.'.length);
  if (!isSystemDomainTagKey(key)) return null;
  return key;
}

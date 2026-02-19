import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/tags/system_domain_tags.dart';
import 'package:secondloop/features/tags/tag_localization.dart';
import 'package:secondloop/src/rust/db.dart';

Tag _tag({
  required String id,
  required String name,
  String? systemKey,
  bool isSystem = false,
}) {
  return Tag(
    id: id,
    name: name,
    systemKey: systemKey,
    isSystem: isSystem,
    color: null,
    createdAtMs: PlatformInt64Util.from(0),
    updatedAtMs: PlatformInt64Util.from(0),
  );
}

void main() {
  test('system domain tags define 10 canonical keys', () {
    expect(kSystemDomainTagKeys.length, 10);
    expect(kSystemDomainTagKeys.toSet().length, 10);
    expect(kSystemDomainTagKeys.first, 'work');
    expect(kSystemDomainTagKeys.last, 'hobby');

    for (final key in kSystemDomainTagKeys) {
      expect(isSystemDomainTagKey(key), isTrue);
      expect(systemDomainTagId(key), 'system.tag.$key');
      expect(systemDomainKeyFromTagId('system.tag.$key'), key);
    }
  });

  test('localizes system domain keys based on locale language', () {
    expect(localizeSystemDomainTagKey(const Locale('en'), 'work'), 'Work');
    expect(localizeSystemDomainTagKey(const Locale('zh', 'CN'), 'work'), '工作');
    expect(
        localizeSystemDomainTagKey(const Locale('zh', 'TW'), 'finance'), '财务');
    expect(localizeSystemDomainTagKey(const Locale('ja'), 'work'), 'Work');
    expect(
        localizeSystemDomainTagKey(const Locale('en'), 'unknown'), 'unknown');
  });

  test('localizeTagName prefers system key and id mapping', () {
    const zh = Locale('zh', 'CN');
    const en = Locale('en');

    final bySystemKey = _tag(
      id: 'custom-1',
      name: 'Work Alias',
      systemKey: 'work',
      isSystem: true,
    );
    final bySystemId = _tag(
      id: 'system.tag.study',
      name: 'study',
      systemKey: null,
      isSystem: true,
    );
    final custom = _tag(
      id: 'custom-2',
      name: '  Focus Session  ',
      systemKey: null,
    );

    expect(localizeTagName(zh, bySystemKey), '工作');
    expect(localizeTagName(en, bySystemKey), 'Work');
    expect(localizeTagName(zh, bySystemId), '学习');
    expect(localizeTagName(en, bySystemId), 'Study');
    expect(localizeTagName(en, custom), 'Focus Session');
  });
}

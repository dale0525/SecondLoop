import 'package:flutter/widgets.dart';

import '../../src/rust/db.dart';
import 'system_domain_tags.dart';

const Map<String, String> _systemTagLabelsEn = <String, String>{
  'work': 'Work',
  'personal': 'Personal',
  'family': 'Family',
  'health': 'Health',
  'finance': 'Finance',
  'study': 'Study',
  'travel': 'Travel',
  'social': 'Social',
  'home': 'Home',
  'hobby': 'Hobby',
};

const Map<String, String> _systemTagLabelsZhCn = <String, String>{
  'work': '工作',
  'personal': '个人',
  'family': '家庭',
  'health': '健康',
  'finance': '财务',
  'study': '学习',
  'travel': '旅行',
  'social': '社交',
  'home': '居家',
  'hobby': '爱好',
};

bool isZhLocale(Locale locale) {
  final language = locale.languageCode.toLowerCase();
  return language.startsWith('zh');
}

String localizeSystemDomainTagKey(Locale locale, String systemKey) {
  final normalized = systemKey.trim();
  final labels = isZhLocale(locale) ? _systemTagLabelsZhCn : _systemTagLabelsEn;
  return labels[normalized] ?? normalized;
}

String localizeTagName(Locale locale, Tag tag) {
  final key = tag.systemKey?.trim();
  if (key != null && key.isNotEmpty && isSystemDomainTagKey(key)) {
    return localizeSystemDomainTagKey(locale, key);
  }

  final fromId = systemDomainKeyFromTagId(tag.id);
  if (fromId != null) {
    return localizeSystemDomainTagKey(locale, fromId);
  }

  final name = tag.name.trim();
  return name.isEmpty ? tag.id : name;
}

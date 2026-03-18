enum TodoFollowupTaskType {
  execution('execution', false),
  research('research', true),
  comparison('comparison', true),
  liveInfoLookup('live_info_lookup', true),
  referenceCollection('reference_collection', true),
  coordination('coordination', false),
  planning('planning', false),
  unknown('unknown', false);

  const TodoFollowupTaskType(this.wireValue, this.allowsAutoFollowup);

  final String wireValue;
  final bool allowsAutoFollowup;

  static TodoFollowupTaskType fromWireValue(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final value in values) {
      if (value.wireValue == normalized) return value;
    }
    return TodoFollowupTaskType.unknown;
  }
}

final List<RegExp> _researchPatterns = <RegExp>[
  RegExp(r'调研|研究|分析|了解|盘点|survey|research|investigate', caseSensitive: false),
];

final List<RegExp> _comparisonPatterns = <RegExp>[
  RegExp(r'对比|比较|选型|benchmark|compare|comparison', caseSensitive: false),
];

final List<RegExp> _referenceCollectionPatterns = <RegExp>[
  RegExp(r'收集资料|搜集资料|官网链接|材料要求|资料要求|收集.*链接|collect.*links?',
      caseSensitive: false),
];

final List<RegExp> _liveInfoLookupPatterns = <RegExp>[
  RegExp(
    r'机场|航班|航站楼|到达时间|停车|入园时间|检票入口|接机|车次|高铁|火车|terminal|arrival|parking',
    caseSensitive: false,
  ),
];

final List<RegExp> _coordinationPatterns = <RegExp>[
  RegExp(r'开会|约时间|沟通|联系|同步|coordinate|meeting', caseSensitive: false),
];

final List<RegExp> _planningPatterns = <RegExp>[
  RegExp(r'计划|安排|规划|roadmap|plan', caseSensitive: false),
];

final List<RegExp> _executionPatterns = <RegExp>[
  RegExp(r'修复|修|提交|发送|付款|上线|实现|fix|ship|submit|pay', caseSensitive: false),
];

TodoFollowupTaskType classifyTodoFollowupTaskType(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return TodoFollowupTaskType.unknown;

  for (final pattern in _comparisonPatterns) {
    if (pattern.hasMatch(text)) return TodoFollowupTaskType.comparison;
  }
  for (final pattern in _referenceCollectionPatterns) {
    if (pattern.hasMatch(text)) return TodoFollowupTaskType.referenceCollection;
  }
  for (final pattern in _liveInfoLookupPatterns) {
    if (pattern.hasMatch(text)) return TodoFollowupTaskType.liveInfoLookup;
  }
  for (final pattern in _researchPatterns) {
    if (pattern.hasMatch(text)) return TodoFollowupTaskType.research;
  }
  for (final pattern in _coordinationPatterns) {
    if (pattern.hasMatch(text)) return TodoFollowupTaskType.coordination;
  }
  for (final pattern in _planningPatterns) {
    if (pattern.hasMatch(text)) return TodoFollowupTaskType.planning;
  }
  for (final pattern in _executionPatterns) {
    if (pattern.hasMatch(text)) return TodoFollowupTaskType.execution;
  }

  return TodoFollowupTaskType.unknown;
}

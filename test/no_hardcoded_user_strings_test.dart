import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/no_hardcoded_user_strings_guard.dart';

void main() {
  test('Flags helper methods that hide hardcoded user-facing strings', () {
    final offenders = scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    Text(_title());
  }

  String _title() => _isZh ? '设置应用锁密码' : 'Set app lock password';

  bool get _isZh => true;
}
''',
      path: 'snippet_helper_method.dart',
    );

    expect(offenders, isNotEmpty);
    expect(offenders.single, contains('indirection'));
  });

  test('Flags helper wrappers with literal copy passed into user-facing sinks',
      () {
    final offenders = scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    InputDecoration(labelText: _text('状态', 'Status'));
  }

  String _text(String zh, String en) => _isZh ? zh : en;

  bool get _isZh => true;
}
''',
      path: 'snippet_helper_wrapper.dart',
    );

    expect(offenders, isNotEmpty);
    expect(offenders.single, contains('indirection'));
  });

  test('Flags locale branches passed directly into user-facing sinks', () {
    final offenders = scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    Text(_isZh ? '设置' : 'Settings');
    InputDecoration(labelText: zh ? '保存' : 'Save');
  }

  bool get _isZh => true;
  bool get zh => true;
}
''',
      path: 'snippet_direct_locale_branch.dart',
    );

    expect(offenders, hasLength(2));
    expect(offenders.first, contains('indirection'));
    expect(offenders.last, contains('indirection'));
  });

  test('Does not flag locale branches inside i18n method arguments', () {
    final offenders = scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    Text(
      context.t.releaseNotes.updatedTo(
        version: hasNotes ? version : 'v$appVersion',
      ),
    );
  }
}
''',
      path: 'snippet_i18n_method_argument.dart',
    );

    expect(offenders, isEmpty);
  });

  test('Flags helper methods declared in sibling part files', () {
    final previousCurrentDir = Directory.current;
    final tempDir = Directory.systemTemp.createTempSync(
      'i18n_guard_part_library_',
    );
    addTearDown(() {
      Directory.current = previousCurrentDir;
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Directory.current = tempDir;
    Directory('lib').createSync();
    File('lib/demo.dart').writeAsStringSync(r'''
library demo;

import 'package:flutter/widgets.dart';

part 'demo_helper.dart';
part 'demo_view.dart';

class DemoWidget {
  const DemoWidget(this.isZh);

  final bool isZh;
}
''');
    File('lib/demo_helper.dart').writeAsStringSync(r'''
part of 'demo.dart';

extension DemoHelper on DemoWidget {
  String titleLabel() => isZh ? '设置' : 'Settings';
}
''');
    File('lib/demo_view.dart').writeAsStringSync(r'''
part of 'demo.dart';

extension DemoView on DemoWidget {
  Widget buildLabel() {
    return Text(titleLabel());
  }
}
''');

    final offenders = scanLibForHardcodedUserFacingStrings();

    expect(offenders, isNotEmpty);
    expect(
      _normalizePathSeparators(offenders.join('\n')),
      contains('lib/demo_view.dart'),
    );
  });

  test('Flags helper parameters forwarded into user-facing sinks', () {
    final offenders = scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    option(title: zh ? '本地 OCR' : 'Local OCR');
  }

  Widget option({required String title}) {
    return Text(title);
  }

  bool get zh => true;
}
''',
      path: 'snippet_helper_parameter_passthrough.dart',
    );

    expect(offenders, isNotEmpty);
    expect(offenders.single, contains('indirection'));
  });

  test('Flags custom wrapper sinks that render user-facing copy', () {
    final offenders = scanSourceForHardcodedUserFacingStrings(
      content: r'''
Widget mediaAnnotationSectionTitle(Object context, String title) => Text(title);

Widget mediaAnnotationCapabilityCard({
  required Object context,
  required String title,
  required String description,
  required String statusLabel,
  required List<Object> actions,
}) {
  return Text(title);
}

class Demo {
  void build(Object context) {
    mediaAnnotationSectionTitle(context, _title());
    mediaAnnotationCapabilityCard(
      context: context,
      title: _title(),
      description: _description(),
      statusLabel: _status(),
      actions: const [],
    );
  }

  String _title() => zh ? '链接内容理解' : 'URL content understanding';
  String _description() => zh ? '先在本地抓取并清洗网页文本。' : 'Preprocess URL content locally.';
  String _status() => zh ? '状态：下载中' : 'Status: downloading';
  bool get zh => true;
}
''',
      path: 'snippet_custom_wrapper_sink.dart',
    );

    expect(offenders, isNotEmpty);
    expect(offenders.join('\n'), contains('indirection'));
  });

  test('Does not flag non-linguistic formatting helpers', () {
    final offenders = scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    Text(_buildIndexLabel());
  }

  String _buildIndexLabel() {
    final current = 1;
    final total = 3;
    return '$current/$total';
  }
}
''',
      path: 'snippet_numeric_format.dart',
    );

    expect(offenders, isEmpty);
  });

  test('Does not flag numeric expressions inside i18n method arguments', () {
    final offenders = scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build(Object context, int index) {
    Text(context.t.chat.agentTasks.itemIndex(value: index + 1));
  }
}
''',
      path: 'snippet_i18n_numeric_argument.dart',
    );

    expect(offenders, isEmpty);
  });

  test('Policy text explicitly warns against bypassing i18n guard', () {
    expect(i18nGuardPolicy, contains('Do not bypass'));
    expect(i18nGuardPolicy, contains('i18n'));
  });

  test('No hardcoded user-facing strings in lib/', () {
    final offenders = scanLibForHardcodedUserFacingStrings();
    expect(offenders, isEmpty, reason: _formatFailureReason(offenders));
  });
}

String _formatFailureReason(List<String> offenders) {
  if (offenders.isEmpty) return i18nGuardPolicy;
  return '$i18nGuardPolicy\n${offenders.join('\n')}';
}

String _normalizePathSeparators(String input) {
  return input.replaceAll('\\', '/');
}

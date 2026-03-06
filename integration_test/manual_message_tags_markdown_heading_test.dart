import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:secondloop/src/rust/api/core.dart' as rust_core;
import 'package:secondloop/src/rust/api/tags.dart' as rust_tags;
import 'package:secondloop/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets('manual tag parsing ignores markdown headings end-to-end', (
    WidgetTester tester,
  ) async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_manual_tags_',
    );
    addTearDown(() async {
      await appDir.delete(recursive: true);
    });

    final key = await rust_core.authInitMasterPassword(
      appDir: appDir.path,
      password: 'test-password',
    );
    final conversation = await rust_core.dbGetOrCreateLoopHomeConversation(
      appDir: appDir.path,
      key: key,
    );
    const content = '#alpha\n\n# 高中语文作文课 V1 功能需求与设计文档\n\n## 1. 文档目的\n';

    final message = await rust_core.dbInsertMessage(
      appDir: appDir.path,
      key: key,
      conversationId: conversation.id,
      role: 'user',
      content: content,
    );

    final manualTagNames = await rust_tags.dbListManualMessageTagNames(
      appDir: appDir.path,
      key: key,
      messageId: message.id,
    );
    expect(manualTagNames, const <String>['alpha']);

    final messageTags = await rust_tags.dbListMessageTags(
      appDir: appDir.path,
      key: key,
      messageId: message.id,
    );
    expect(
      messageTags.map((tag) => tag.name.toLowerCase()).toList(growable: false),
      const <String>['alpha'],
    );

    await rust_tags.dbDeleteTag(
      appDir: appDir.path,
      key: key,
      tagId: messageTags.single.id,
    );

    final reloaded = await rust_core.dbGetMessageById(
      appDir: appDir.path,
      key: key,
      messageId: message.id,
    );
    expect(reloaded, isNotNull);
    expect(
      reloaded!.content,
      '\n# 高中语文作文课 V1 功能需求与设计文档\n\n## 1. 文档目的\n',
    );
  });
}

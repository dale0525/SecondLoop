import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_edit_policy.dart';

void main() {
  test('edit policy: does not requeue when message is not source entry', () {
    final shouldRequeue = shouldRequeueSemanticParseAfterMessageEdit(
      previousText: 'buy milk tomorrow',
      editedText: 'buy milk on Friday',
      isSourceEntry: false,
    );

    expect(shouldRequeue, isFalse);
  });

  test('edit policy: does not requeue for punctuation-only changes', () {
    final shouldRequeue = shouldRequeueSemanticParseAfterMessageEdit(
      previousText: 'Buy milk tomorrow!',
      editedText: '  buy milk tomorrow  ',
      isSourceEntry: true,
    );

    expect(shouldRequeue, isFalse);
  });

  test('edit policy: does not requeue for non todo-relevant text', () {
    final shouldRequeue = shouldRequeueSemanticParseAfterMessageEdit(
      previousText: 'buy milk tomorrow',
      editedText: 'Is this done?',
      isSourceEntry: true,
    );

    expect(shouldRequeue, isFalse);
  });

  test('edit policy: requeues for meaningful source-entry edits', () {
    final shouldRequeue = shouldRequeueSemanticParseAfterMessageEdit(
      previousText: 'pay rent next Monday',
      editedText: 'pay rent this Friday',
      isSourceEntry: true,
    );

    expect(shouldRequeue, isTrue);
  });

  test('todo relevance: bare status update is filtered out', () {
    expect(looksLikeTodoRelevantForSemanticParse('done'), isFalse);
    expect(looksLikeTodoRelevantForSemanticParse('完成了'), isFalse);
  });
}

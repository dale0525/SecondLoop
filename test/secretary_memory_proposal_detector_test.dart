import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/secretary/memory_proposal_detector.dart';

void main() {
  group('MemoryProposalDetector', () {
    const detector = MemoryProposalDetector();

    test('detects explicit English remember preference', () {
      final proposal = detector.detect(
        messageId: 'm1',
        text: 'Remember that I prefer morning meetings.',
        createdAtMs: 10,
      );

      expect(proposal, isNotNull);
      expect(proposal!.kind, 'preference');
      expect(proposal.title, contains('morning meetings'));
      expect(proposal.body, contains('prefer morning meetings'));
      expect(proposal.sourceMessageId, 'm1');
      expect(proposal.confidence, greaterThanOrEqualTo(0.8));
    });

    test('detects explicit Chinese remember preference', () {
      final proposal = detector.detect(
        messageId: 'm2',
        text: '记住，我更喜欢上午开会。',
        createdAtMs: 20,
      );

      expect(proposal, isNotNull);
      expect(proposal!.kind, 'preference');
      expect(proposal.title, contains('上午开会'));
      expect(proposal.body, contains('我更喜欢上午开会'));
    });

    test('detects replacement memory hints', () {
      final proposal = detector.detect(
        messageId: 'm3',
        text: 'Actually, I no longer work with Alice.',
        createdAtMs: 30,
      );

      expect(proposal, isNotNull);
      expect(proposal!.kind, 'fact');
      expect(proposal.actionHint, 'update');
      expect(proposal.body, contains('no longer work with Alice'));
    });

    test('ignores external action requests and vague notes', () {
      expect(
        detector.detect(
          messageId: 'm4',
          text: 'send this to Alice',
          createdAtMs: 40,
        ),
        isNull,
      );
      expect(
        detector.detect(
          messageId: 'm5',
          text: 'maybe useful later',
          createdAtMs: 50,
        ),
        isNull,
      );
    });

    test('weak preference hints are opt-in for AI routing', () {
      expect(
        detector.detect(
          messageId: 'm6',
          text: '下午开会我效率很差。',
          createdAtMs: 60,
        ),
        isNull,
      );

      final proposal = detector.detect(
        messageId: 'm6',
        text: '下午开会我效率很差。',
        createdAtMs: 60,
        includeWeakSignals: true,
      );

      expect(proposal, isNotNull);
      expect(proposal!.kind, 'preference');
      expect(proposal.confidence, lessThan(0.7));
      expect(proposal.body, contains('下午开会'));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/attachment_annotation_job_status_row.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('AttachmentAnnotationJobStatusRow shows running after soft delay',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'abc',
      status: 'pending',
      lang: 'en',
      modelName: null,
      attempts: 0,
      nextRetryAtMs: null,
      lastError: null,
      createdAtMs: now,
      updatedAtMs: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('AI analyzing…'), findsNothing);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('AI analyzing…'), findsOneWidget);
  });
}

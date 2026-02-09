import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_card.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/ui/sl_surface.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('AttachmentCard renders basic metadata', (tester) async {
    const attachment = Attachment(
      sha256: 'abc',
      mimeType: 'image/png',
      path: 'attachments/abc.bin',
      byteLen: 12,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: Scaffold(
            body: AttachmentCard(attachment: attachment),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('abc'), findsOneWidget);
    expect(find.text('12 B'), findsNothing);
    expect(find.byType(SlSurface), findsOneWidget);
  });
}

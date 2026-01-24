import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_card.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/ui/sl_surface.dart';

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
      const MaterialApp(
        home: Scaffold(
          body: AttachmentCard(attachment: attachment),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('image/png'), findsOneWidget);
    expect(find.byType(SlSurface), findsOneWidget);
  });
}

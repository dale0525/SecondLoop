import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/features/settings/vault_usage_card.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Vault attachment usage list sorts desc and fires actions', (
    tester,
  ) async {
    VaultAttachmentUsageItem? opened;
    VaultAttachmentUsageItem? deleted;

    final items = <VaultAttachmentUsageItem>[
      const VaultAttachmentUsageItem(
        sha256: 'sha_small',
        mimeType: 'image/png',
        byteLen: 128,
        createdAtMs: 100,
        uploadedAtMs: 200,
      ),
      const VaultAttachmentUsageItem(
        sha256: 'sha_large',
        mimeType: 'application/pdf',
        byteLen: 4096,
        createdAtMs: 150,
        uploadedAtMs: 250,
      ),
    ];

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: VaultAttachmentUsageListView(
              items: items,
              deletingSha: null,
              onOpen: (item) => opened = item,
              onDelete: (item) => deleted = item,
            ),
          ),
        ),
      ),
    );

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(
      (tiles.first.key as ValueKey).value,
      'vault_usage_attachment_sha_large',
    );
    expect(
      (tiles.last.key as ValueKey).value,
      'vault_usage_attachment_sha_small',
    );

    await tester
        .tap(find.byKey(const ValueKey('vault_usage_attachment_sha_large')));
    await tester.pump();

    expect(opened?.sha256, 'sha_large');

    await tester.tap(
      find.byKey(
        const ValueKey('vault_usage_attachment_delete_sha_large'),
      ),
    );
    await tester.pump();

    expect(deleted?.sha256, 'sha_large');
  });
}

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
    VaultAttachmentUsageItem? previewed;
    VaultAttachmentUsageItem? cacheCleared;

    final items = <VaultAttachmentUsageItem>[
      const VaultAttachmentUsageItem(
        id: 'att-small',
        sha256: 'sha_small',
        displayName: 'small.png',
        mimeType: 'image/png',
        byteLen: 128,
        createdAtMs: 100,
        uploadedAtMs: 200,
        linkedEntities: [
          VaultAttachmentLinkedEntity(
            kind: 'note',
            id: 'note-1',
            title: 'Small note',
          ),
        ],
        processingStatus: 'ready',
      ),
      const VaultAttachmentUsageItem(
        id: 'att-large',
        sha256: 'sha_large',
        displayName: 'large.pdf',
        mimeType: 'application/pdf',
        byteLen: 4096,
        createdAtMs: 150,
        uploadedAtMs: 250,
        linkedEntities: [
          VaultAttachmentLinkedEntity(
            kind: 'note',
            id: 'note-2',
            title: 'Large note',
          ),
        ],
        processingStatus: 'processing',
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
              onPreview: (item) => previewed = item,
              onClearLocalCache: (item) => cacheCleared = item,
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
    expect(find.text('large.pdf'), findsOneWidget);
    expect(find.textContaining('application/pdf'), findsOneWidget);
    expect(find.textContaining('Large note'), findsOneWidget);
    expect(find.textContaining('processing'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('vault_usage_attachment_preview_att-large'),
      ),
    );
    await tester.pump();

    expect(previewed?.id, 'att-large');

    await tester.tap(
      find.byKey(
        const ValueKey('vault_usage_attachment_clear_cache_att-large'),
      ),
    );
    await tester.pump();

    expect(cacheCleared?.id, 'att-large');

    await tester.tap(
      find.byKey(
        const ValueKey('vault_usage_attachment_delete_att-large'),
      ),
    );
    await tester.pump();

    expect(deleted?.sha256, 'sha_large');
  });

  testWidgets(
      'Vault attachment usage list marks web-only media with continue-in-app hint',
      (
    tester,
  ) async {
    final items = <VaultAttachmentUsageItem>[
      const VaultAttachmentUsageItem(
        sha256: 'sha_pdf',
        mimeType: 'application/pdf',
        byteLen: 1024,
        createdAtMs: 100,
        uploadedAtMs: 200,
      ),
      const VaultAttachmentUsageItem(
        sha256: 'sha_image',
        mimeType: 'image/png',
        byteLen: 512,
        createdAtMs: 90,
        uploadedAtMs: 190,
      ),
    ];

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: VaultAttachmentUsageListView(
              items: items,
              deletingSha: null,
              isWebOverride: true,
              onOpen: (_) {},
              onDelete: (_) {},
              onPreview: (_) {},
              onClearLocalCache: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Continue in App'), findsOneWidget);
  });

  testWidgets(
      'Vault attachment usage list hides continue-in-app hint outside web', (
    tester,
  ) async {
    final items = <VaultAttachmentUsageItem>[
      const VaultAttachmentUsageItem(
        sha256: 'sha_pdf',
        mimeType: 'application/pdf',
        byteLen: 1024,
        createdAtMs: 100,
        uploadedAtMs: 200,
      ),
    ];

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: VaultAttachmentUsageListView(
              items: items,
              deletingSha: null,
              isWebOverride: false,
              onOpen: (_) {},
              onDelete: (_) {},
              onPreview: (_) {},
              onClearLocalCache: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Continue in App'), findsNothing);
  });

  testWidgets(
      'Vault attachment usage list renders grouped video entries by root sha', (
    tester,
  ) async {
    VaultAttachmentUsageItem? opened;
    VaultAttachmentUsageItem? deleted;

    final items = <VaultAttachmentUsageItem>[
      const VaultAttachmentUsageItem(
        sha256: 'sha-video-segment',
        rootSha256: 'sha-video-root',
        groupType: 'video',
        leafCount: 5,
        mimeType: 'video',
        byteLen: 2680,
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
              onPreview: (_) {},
              onClearLocalCache: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('vault_usage_attachment_sha-video-root')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('vault_usage_attachment_delete_sha-video-root'),
      ),
      findsOneWidget,
    );
    expect(find.text('Video'), findsOneWidget);
    expect(find.textContaining('2.6 KB'), findsOneWidget);
    expect(find.textContaining('5×'), findsOneWidget);
    expect(find.textContaining('sha-video-ro…'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('vault_usage_attachment_sha-video-root')),
    );
    await tester.pump();
    expect(opened?.rootSha256, 'sha-video-root');

    await tester.tap(
      find.byKey(
        const ValueKey('vault_usage_attachment_delete_sha-video-root'),
      ),
    );
    await tester.pump();
    expect(deleted?.rootSha256, 'sha-video-root');
  });

  testWidgets('Vault attachment usage list exposes type and sort filters', (
    tester,
  ) async {
    String? selectedType = 'image';
    VaultAttachmentUsageSort? selectedSort;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: VaultAttachmentUsageListView(
              items: const [
                VaultAttachmentUsageItem(
                  id: 'att-image',
                  sha256: 'sha-image',
                  displayName: 'image.png',
                  mimeType: 'image/png',
                  byteLen: 512,
                  createdAtMs: 100,
                  uploadedAtMs: 200,
                ),
                VaultAttachmentUsageItem(
                  id: 'att-pdf',
                  sha256: 'sha-pdf',
                  displayName: 'doc.pdf',
                  mimeType: 'application/pdf',
                  byteLen: 2048,
                  createdAtMs: 100,
                  uploadedAtMs: 200,
                ),
              ],
              deletingSha: null,
              typeFilter: selectedType,
              sort: VaultAttachmentUsageSort.uploadedDesc,
              onTypeFilterChanged: (value) => selectedType = value,
              onSortChanged: (value) => selectedSort = value,
              onOpen: (_) {},
              onDelete: (_) {},
              onPreview: (_) {},
              onClearLocalCache: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('image.png'), findsOneWidget);
    expect(find.text('doc.pdf'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('vault_usage_type_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All types').last);
    await tester.pumpAndSettle();
    expect(selectedType, isNull);

    await tester.tap(find.byKey(const ValueKey('vault_usage_sort_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Size').last);
    await tester.pumpAndSettle();
    expect(selectedSort, VaultAttachmentUsageSort.sizeDesc);
  });

  testWidgets('Upload time sort uses uploadedAtMs before createdAtMs', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: VaultAttachmentUsageListView(
              items: const [
                VaultAttachmentUsageItem(
                  id: 'att-created-newer',
                  sha256: 'sha-created-newer',
                  displayName: 'created-newer.pdf',
                  mimeType: 'application/pdf',
                  byteLen: 1024,
                  createdAtMs: 9000,
                  uploadedAtMs: 1000,
                ),
                VaultAttachmentUsageItem(
                  id: 'att-uploaded-newer',
                  sha256: 'sha-uploaded-newer',
                  displayName: 'uploaded-newer.pdf',
                  mimeType: 'application/pdf',
                  byteLen: 512,
                  createdAtMs: 1000,
                  uploadedAtMs: 9000,
                ),
              ],
              deletingSha: null,
              sort: VaultAttachmentUsageSort.uploadedDesc,
              onOpen: (_) {},
              onDelete: (_) {},
              onPreview: (_) {},
              onClearLocalCache: (_) {},
            ),
          ),
        ),
      ),
    );

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(
      (tiles.first.key as ValueKey).value,
      'vault_usage_attachment_sha-uploaded-newer',
    );
    expect(
      (tiles.last.key as ValueKey).value,
      'vault_usage_attachment_sha-created-newer',
    );
  });
}

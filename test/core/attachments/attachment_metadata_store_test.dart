import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/attachments/attachment_metadata_store.dart';

void main() {
  group('DartAttachmentMetadataStore', () {
    late DartAttachmentMetadataStore store;
    late Uint8List keyA;
    late Uint8List keyB;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = const DartAttachmentMetadataStore();
      keyA = Uint8List.fromList(List<int>.filled(32, 1));
      keyB = Uint8List.fromList(List<int>.filled(32, 2));
    });

    test('persists title and source metadata in Dart storage', () async {
      await store.upsert(
        keyA,
        attachmentSha256: 'sha-1',
        title: 'Receipt',
        filenames: const <String>['receipt.pdf'],
        sourceUrls: const <String>['https://example.test/receipt'],
      );

      final metadata = await store.read(keyA, attachmentSha256: 'sha-1');

      expect(metadata?.title, 'Receipt');
      expect(metadata?.filenames, const <String>['receipt.pdf']);
      expect(
          metadata?.sourceUrls, const <String>['https://example.test/receipt']);
      expect(metadata?.createdAtMs, greaterThan(0));
      expect(metadata?.updatedAtMs, greaterThan(0));
    });

    test('namespaces metadata by session key', () async {
      await store.upsert(
        keyA,
        attachmentSha256: 'same-sha',
        title: 'Vault A',
      );
      await store.upsert(
        keyB,
        attachmentSha256: 'same-sha',
        title: 'Vault B',
      );

      expect(
        (await store.read(keyA, attachmentSha256: 'same-sha'))?.title,
        'Vault A',
      );
      expect(
        (await store.read(keyB, attachmentSha256: 'same-sha'))?.title,
        'Vault B',
      );
    });
  });
}

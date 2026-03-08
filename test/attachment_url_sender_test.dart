import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/attachments/attachment_metadata_store.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/features/attachments/attachment_ingest_pipeline.dart';
import 'package:secondloop/features/attachments/attachment_url_sender.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('trySendUrlManifestAttachment inserts manifest and upserts metadata',
      () async {
    final backend = _UrlSenderBackend();
    final metadataStore = _FakeAttachmentMetadataStore();
    final linkCalls = <String>[];
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final sent = await trySendUrlManifestAttachment(
      text: 'https://example.com/path',
      backend: backend,
      sessionKey: sessionKey,
      metadataStore: metadataStore,
      linkCreatedAttachment: (attachmentSha256, normalizedUrl) async {
        linkCalls.add('$attachmentSha256|$normalizedUrl');
      },
    );

    expect(sent, isTrue);
    expect(backend.insertedMimeTypes, [kSecondLoopUrlManifestMimeType]);
    expect(linkCalls, ['sha_1|https://example.com/path']);
    expect(metadataStore.upsertCalls, hasLength(1));
    final upsert = metadataStore.upsertCalls.single;
    expect(upsert.sha256, 'sha_1');
    expect(upsert.title, 'https://example.com/path');
    expect(upsert.filenames, isEmpty);
    expect(upsert.sourceUrls, ['https://example.com/path']);
  });

  test('trySendUrlManifestAttachment ignores non-url text', () async {
    final backend = _UrlSenderBackend();
    final metadataStore = _FakeAttachmentMetadataStore();
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final sent = await trySendUrlManifestAttachment(
      text: 'not a url',
      backend: backend,
      sessionKey: sessionKey,
      metadataStore: metadataStore,
      linkCreatedAttachment: (_, __) async {},
    );

    expect(sent, isFalse);
    expect(backend.insertedMimeTypes, isEmpty);
    expect(metadataStore.upsertCalls, isEmpty);
  });
}

final class _UrlSenderBackend extends NativeAppBackend {
  _UrlSenderBackend()
      : super(appDirProvider: () async => '/tmp/secondloop_test');

  final List<String> insertedMimeTypes = <String>[];

  @override
  Future<Attachment> insertAttachment(
    Uint8List key, {
    required Uint8List bytes,
    required String mimeType,
  }) async {
    insertedMimeTypes.add(mimeType);
    return Attachment(
      sha256: 'sha_${insertedMimeTypes.length}',
      mimeType: mimeType,
      path: 'attachments/sha_${insertedMimeTypes.length}.bin',
      byteLen: bytes.length,
      createdAtMs: 0,
    );
  }
}

final class _FakeAttachmentMetadataStore implements AttachmentMetadataStore {
  final List<
      ({
        String sha256,
        String? title,
        List<String> filenames,
        List<String> sourceUrls,
      })> upsertCalls = <({
    String sha256,
    String? title,
    List<String> filenames,
    List<String> sourceUrls,
  })>[];

  @override
  Future<AttachmentMetadata?> read(
    Uint8List key, {
    required String attachmentSha256,
  }) async =>
      null;

  @override
  Future<void> upsert(
    Uint8List key, {
    required String attachmentSha256,
    String? title,
    List<String> filenames = const <String>[],
    List<String> sourceUrls = const <String>[],
  }) async {
    upsertCalls.add(
      (
        sha256: attachmentSha256,
        title: title,
        filenames: filenames,
        sourceUrls: sourceUrls,
      ),
    );
  }
}

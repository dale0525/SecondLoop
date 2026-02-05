import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/features/share/share_ingest.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  test('ShareIngest drains url+file items into Main Stream with attachments',
      () async {
    SharedPreferences.setMockInitialValues({});

    final backend = _ShareBackend();
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final dir = await Directory.systemTemp.createTemp('secondloop_share_');
    addTearDown(() async => dir.delete(recursive: true));

    final file = File('${dir.path}/report.pdf');
    await file.writeAsBytes([1, 2, 3, 4]);

    await ShareIngest.enqueueUrl('https://example.com');
    await ShareIngest.enqueueFile(
      tempPath: file.path,
      mimeType: 'application/pdf',
      filename: 'report.pdf',
    );

    final upsertCalls =
        <({String sha256, ShareIngestAttachmentMetadata meta})>[];

    String? urlManifestUrl;
    String? drainedFilePath;
    String? drainedFileMimeType;
    String? drainedFileName;

    final processed = await ShareIngest.drainQueue(
      backend,
      sessionKey,
      onUrlManifest: (url) async {
        urlManifestUrl = url;
        return 'sha_url_manifest';
      },
      onFile: (path, mimeType, filename) async {
        drainedFilePath = path;
        drainedFileMimeType = mimeType;
        drainedFileName = filename;
        await File(path).delete();
        return 'sha_file';
      },
      onUpsertAttachmentMetadata: (sha256, meta) async {
        upsertCalls.add((sha256: sha256, meta: meta));
      },
    );

    expect(processed, 2);
    expect(urlManifestUrl, 'https://example.com');
    expect(drainedFilePath, file.path);
    expect(drainedFileMimeType, 'application/pdf');
    expect(drainedFileName, 'report.pdf');
    expect(await file.exists(), false);

    expect(backend.insertedContents, [
      'https://example.com',
      'Shared file: report.pdf',
    ]);
    expect(backend.linkCalls, [
      'm1:sha_url_manifest',
      'm2:sha_file',
    ]);

    expect(upsertCalls.length, 2);
    expect(
      upsertCalls.first,
      (
        sha256: 'sha_url_manifest',
        meta: const ShareIngestAttachmentMetadata(
          title: 'https://example.com',
          sourceUrls: ['https://example.com'],
        ),
      ),
    );
    expect(
      upsertCalls.last,
      (
        sha256: 'sha_file',
        meta: const ShareIngestAttachmentMetadata(
          filenames: ['report.pdf'],
        ),
      ),
    );
  });
}

final class _ShareBackend extends TestAppBackend implements AttachmentsBackend {
  final List<String> insertedContents = <String>[];
  final List<String> linkCalls = <String>[];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    final message = await super.insertMessage(
      key,
      conversationId,
      role: role,
      content: content,
    );
    insertedContents.add(content);
    return message;
  }

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async =>
      const <Attachment>[];

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {
    linkCalls.add('$messageId:$attachmentSha256');
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
          Uint8List key, String messageId) async =>
      const <Attachment>[];

  @override
  Future<Uint8List> readAttachmentBytes(Uint8List key,
          {required String sha256}) async =>
      Uint8List(0);

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<void> editMessage(
          Uint8List key, String messageId, String content) async =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) async =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <SimilarMessage>[];
}

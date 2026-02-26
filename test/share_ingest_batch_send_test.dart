import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/features/share/share_ingest.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  test('ShareIngest batches text and multiple files into one message',
      () async {
    SharedPreferences.setMockInitialValues({});

    final backend = _ShareBackend();
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final dir = await Directory.systemTemp.createTemp('secondloop_share_');
    addTearDown(() async => dir.delete(recursive: true));

    final fileA = File('${dir.path}/a.txt');
    await fileA.writeAsString('A');
    final fileB = File('${dir.path}/b.txt');
    await fileB.writeAsString('B');

    await ShareIngest.enqueueText('from-share');
    await ShareIngest.enqueueFile(
      tempPath: fileA.path,
      mimeType: 'text/plain',
      filename: 'a.txt',
    );
    await ShareIngest.enqueueFile(
      tempPath: fileB.path,
      mimeType: 'text/plain',
      filename: 'b.txt',
    );

    final processed = await ShareIngest.drainQueue(
      backend,
      sessionKey,
      onFile: (path, _, __) async {
        if (path.endsWith('a.txt')) return 'sha_a';
        if (path.endsWith('b.txt')) return 'sha_b';
        return 'sha_unknown';
      },
    );

    expect(processed, 3);
    expect(backend.insertedContents, const <String>['from-share']);
    expect(backend.linkCalls, const <String>['m1:sha_a', 'm1:sha_b']);
  });

  test('ShareIngest batches url and file into one message', () async {
    SharedPreferences.setMockInitialValues({});

    final backend = _ShareBackend();
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final dir = await Directory.systemTemp.createTemp('secondloop_share_');
    addTearDown(() async => dir.delete(recursive: true));

    final file = File('${dir.path}/report.pdf');
    await file.writeAsBytes(<int>[1, 2, 3]);

    await ShareIngest.enqueueUrl('https://example.com');
    await ShareIngest.enqueueFile(
      tempPath: file.path,
      mimeType: 'application/pdf',
      filename: 'report.pdf',
    );

    final upsertCalls =
        <({String sha256, ShareIngestAttachmentMetadata metadata})>[];
    final processed = await ShareIngest.drainQueue(
      backend,
      sessionKey,
      onUrlManifest: (_) async => 'sha_url',
      onFile: (_, __, ___) async => 'sha_file',
      onUpsertAttachmentMetadata: (sha256, metadata) async {
        upsertCalls.add((sha256: sha256, metadata: metadata));
      },
    );

    expect(processed, 2);
    expect(backend.insertedContents, const <String>['https://example.com']);
    expect(backend.linkCalls, const <String>['m1:sha_url', 'm1:sha_file']);
    expect(
      upsertCalls,
      const <({String sha256, ShareIngestAttachmentMetadata metadata})>[
        (
          sha256: 'sha_url',
          metadata: ShareIngestAttachmentMetadata(
            title: 'https://example.com',
            sourceUrls: <String>['https://example.com'],
          ),
        ),
        (
          sha256: 'sha_file',
          metadata: ShareIngestAttachmentMetadata(
            filenames: <String>['report.pdf'],
          ),
        ),
      ],
    );
  });

  test('ShareIngest dedupes repeated file sha within one drain batch',
      () async {
    SharedPreferences.setMockInitialValues({});

    final backend = _ShareBackend();
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    final dir = await Directory.systemTemp.createTemp('secondloop_share_');
    addTearDown(() async => dir.delete(recursive: true));

    final fileA = File('${dir.path}/dup-a.txt');
    await fileA.writeAsString('A');
    final fileB = File('${dir.path}/dup-b.txt');
    await fileB.writeAsString('B');

    await ShareIngest.enqueueFile(
      tempPath: fileA.path,
      mimeType: 'text/plain',
      filename: 'dup-a.txt',
    );
    await ShareIngest.enqueueFile(
      tempPath: fileB.path,
      mimeType: 'text/plain',
      filename: 'dup-b.txt',
    );

    final processed = await ShareIngest.drainQueue(
      backend,
      sessionKey,
      onFile: (_, __, ___) async => 'sha_same',
    );

    expect(processed, 2);
    expect(backend.insertedContents, const <String>['']);
    expect(backend.linkCalls, const <String>['m1:sha_same']);
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
    Uint8List key,
    String messageId,
  ) async =>
      const <Attachment>[];

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async =>
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
}

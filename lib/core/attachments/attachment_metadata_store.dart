import 'dart:typed_data';

import '../backend/native_app_dir.dart';
import '../../src/rust/api/attachments.dart' as rust_attachments;
import '../../src/rust/db.dart';

abstract class AttachmentMetadataStore {
  Future<AttachmentMetadata?> read(
    Uint8List key, {
    required String attachmentSha256,
  });

  Future<void> upsert(
    Uint8List key, {
    required String attachmentSha256,
    String? title,
    List<String> filenames = const <String>[],
    List<String> sourceUrls = const <String>[],
  });
}

final class RustAttachmentMetadataStore implements AttachmentMetadataStore {
  const RustAttachmentMetadataStore({this.appDirProvider = getNativeAppDir});

  final Future<String> Function() appDirProvider;

  @override
  Future<AttachmentMetadata?> read(
    Uint8List key, {
    required String attachmentSha256,
  }) async {
    final appDir = await appDirProvider();
    return rust_attachments.dbReadAttachmentMetadata(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
    );
  }

  @override
  Future<void> upsert(
    Uint8List key, {
    required String attachmentSha256,
    String? title,
    List<String> filenames = const <String>[],
    List<String> sourceUrls = const <String>[],
  }) async {
    final appDir = await appDirProvider();
    await rust_attachments.dbUpsertAttachmentMetadata(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      title: title,
      filenames: filenames,
      sourceUrls: sourceUrls,
    );
  }
}

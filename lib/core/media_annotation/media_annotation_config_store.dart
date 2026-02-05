import 'dart:typed_data';

import '../backend/native_app_dir.dart';
import '../../src/rust/api/media_annotation.dart' as rust_media_annotation;
import '../../src/rust/db.dart';

abstract class MediaAnnotationConfigStore {
  Future<MediaAnnotationConfig> read(Uint8List key);
  Future<void> write(Uint8List key, MediaAnnotationConfig config);
}

final class RustMediaAnnotationConfigStore
    implements MediaAnnotationConfigStore {
  const RustMediaAnnotationConfigStore({this.appDirProvider = getNativeAppDir});

  final Future<String> Function() appDirProvider;

  @override
  Future<MediaAnnotationConfig> read(Uint8List key) async {
    final appDir = await appDirProvider();
    return rust_media_annotation.dbGetMediaAnnotationConfig(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<void> write(Uint8List key, MediaAnnotationConfig config) async {
    final appDir = await appDirProvider();
    await rust_media_annotation.dbSetMediaAnnotationConfig(
      appDir: appDir,
      key: key,
      config: config,
    );
  }
}

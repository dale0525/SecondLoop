import 'dart:typed_data';

import '../backend/native_app_dir.dart';
import '../../src/rust/api/content_enrichment.dart' as rust_content_enrichment;
import '../../src/rust/db.dart';

abstract class ContentEnrichmentConfigStore {
  Future<ContentEnrichmentConfig> readContentEnrichment(Uint8List key);
  Future<void> writeContentEnrichment(
      Uint8List key, ContentEnrichmentConfig config);

  Future<StoragePolicyConfig> readStoragePolicy(Uint8List key);
  Future<void> writeStoragePolicy(Uint8List key, StoragePolicyConfig config);
}

final class RustContentEnrichmentConfigStore
    implements ContentEnrichmentConfigStore {
  const RustContentEnrichmentConfigStore(
      {this.appDirProvider = getNativeAppDir});

  final Future<String> Function() appDirProvider;

  @override
  Future<ContentEnrichmentConfig> readContentEnrichment(Uint8List key) async {
    final appDir = await appDirProvider();
    return rust_content_enrichment.dbGetContentEnrichmentConfig(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<void> writeContentEnrichment(
    Uint8List key,
    ContentEnrichmentConfig config,
  ) async {
    final appDir = await appDirProvider();
    await rust_content_enrichment.dbSetContentEnrichmentConfig(
      appDir: appDir,
      key: key,
      config: config,
    );
  }

  @override
  Future<StoragePolicyConfig> readStoragePolicy(Uint8List key) async {
    final appDir = await appDirProvider();
    return rust_content_enrichment.dbGetStoragePolicyConfig(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<void> writeStoragePolicy(
    Uint8List key,
    StoragePolicyConfig config,
  ) async {
    final appDir = await appDirProvider();
    await rust_content_enrichment.dbSetStoragePolicyConfig(
      appDir: appDir,
      key: key,
      config: config,
    );
  }
}

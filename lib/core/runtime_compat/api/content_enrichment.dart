import '../../models/app_models.dart';

Future<ContentEnrichmentConfig> dbGetContentEnrichmentConfig(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbGetContentEnrichmentConfig');

Future<void> dbSetContentEnrichmentConfig(
        {required String appDir,
        required List<int> key,
        required ContentEnrichmentConfig config}) =>
    throw UnsupportedError('rust_runtime_removed:dbSetContentEnrichmentConfig');

Future<StoragePolicyConfig> dbGetStoragePolicyConfig(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbGetStoragePolicyConfig');

Future<void> dbSetStoragePolicyConfig(
        {required String appDir,
        required List<int> key,
        required StoragePolicyConfig config}) =>
    throw UnsupportedError('rust_runtime_removed:dbSetStoragePolicyConfig');

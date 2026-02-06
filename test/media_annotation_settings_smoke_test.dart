import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/content_enrichment/content_enrichment_config_store.dart';
import 'package:secondloop/core/media_annotation/media_annotation_config_store.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/media_annotation_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

final class _FakeMediaAnnotationConfigStore
    implements MediaAnnotationConfigStore {
  _FakeMediaAnnotationConfigStore(this._config);

  MediaAnnotationConfig _config;
  final List<MediaAnnotationConfig> writes = <MediaAnnotationConfig>[];

  @override
  Future<MediaAnnotationConfig> read(Uint8List key) async => _config;

  @override
  Future<void> write(Uint8List key, MediaAnnotationConfig config) async {
    _config = config;
    writes.add(config);
  }
}

final class _FakeContentEnrichmentConfigStore
    implements ContentEnrichmentConfigStore {
  _FakeContentEnrichmentConfigStore(this._config);

  ContentEnrichmentConfig _config;
  final List<ContentEnrichmentConfig> writes = <ContentEnrichmentConfig>[];

  @override
  Future<ContentEnrichmentConfig> readContentEnrichment(Uint8List key) async =>
      _config;

  @override
  Future<void> writeContentEnrichment(
    Uint8List key,
    ContentEnrichmentConfig config,
  ) async {
    _config = config;
    writes.add(config);
  }

  @override
  Future<StoragePolicyConfig> readStoragePolicy(Uint8List key) async {
    return const StoragePolicyConfig(
      autoPurgeEnabled: false,
      autoPurgeKeepRecentDays: 30,
      autoPurgeMaxCacheBytes: 0,
      autoPurgeMinCandidateBytes: 0,
      autoPurgeIncludeImages: true,
    );
  }

  @override
  Future<void> writeStoragePolicy(
    Uint8List key,
    StoragePolicyConfig config,
  ) async {}
}

ContentEnrichmentConfig _defaultContentConfig() {
  return const ContentEnrichmentConfig(
    urlFetchEnabled: true,
    documentExtractEnabled: true,
    documentKeepOriginalMaxBytes: 104857600,
    pdfCompressEnabled: true,
    pdfCompressProfile: 'balanced',
    pdfCompressMinBytes: 1048576,
    pdfCompressTargetMaxBytes: 10485760,
    audioTranscribeEnabled: false,
    audioTranscribeEngine: 'whisper',
    videoExtractEnabled: true,
    videoProxyEnabled: true,
    videoProxyMaxDurationMs: 600000,
    videoProxyMaxBytes: 209715200,
    ocrEnabled: true,
    ocrEngineMode: 'auto',
    ocrLanguageHints: '',
    ocrPdfDpi: 200,
    ocrPdfAutoMaxPages: 20,
    ocrPdfMaxPages: 100,
    mobileBackgroundEnabled: true,
    mobileBackgroundRequiresWifi: true,
    mobileBackgroundRequiresCharging: false,
  );
}

void main() {
  testWidgets('Media annotation settings shows image and audio switches',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      const MediaAnnotationConfig(
        annotateEnabled: false,
        searchEnabled: false,
        allowCellular: false,
        providerMode: 'follow_ask_ai',
      ),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(),
    );

    await tester.pumpWidget(
      SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: wrapWithI18n(
          MaterialApp(
            home: Scaffold(
              body: MediaAnnotationSettingsPage(
                configStore: store,
                contentConfigStore: contentStore,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(MediaAnnotationSettingsPage.annotateSwitchKey),
        findsOneWidget);
    expect(find.byKey(MediaAnnotationSettingsPage.searchSwitchKey),
        findsOneWidget);
    expect(
      find.byKey(MediaAnnotationSettingsPage.audioTranscribeSwitchKey),
      findsOneWidget,
    );
  });

  testWidgets('Search toggle asks for confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      const MediaAnnotationConfig(
        annotateEnabled: true,
        searchEnabled: false,
        allowCellular: false,
        providerMode: 'follow_ask_ai',
      ),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(),
    );

    await tester.pumpWidget(
      SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: wrapWithI18n(
          MaterialApp(
            home: Scaffold(
              body: MediaAnnotationSettingsPage(
                configStore: store,
                contentConfigStore: contentStore,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final searchSwitch =
        find.byKey(MediaAnnotationSettingsPage.searchSwitchKey);
    await tester.ensureVisible(searchSwitch);
    await tester.pumpAndSettle();
    await tester.tap(searchSwitch);
    await tester.pumpAndSettle();

    expect(find.byKey(MediaAnnotationSettingsPage.searchConfirmDialogKey),
        findsOneWidget);

    await tester
        .tap(find.byKey(MediaAnnotationSettingsPage.searchConfirmCancelKey));
    await tester.pumpAndSettle();

    expect(find.byKey(MediaAnnotationSettingsPage.searchConfirmDialogKey),
        findsNothing);
  });

  testWidgets('Audio transcribe switch writes content enrichment config',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      const MediaAnnotationConfig(
        annotateEnabled: false,
        searchEnabled: false,
        allowCellular: false,
        providerMode: 'follow_ask_ai',
      ),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(),
    );

    await tester.pumpWidget(
      SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: wrapWithI18n(
          MaterialApp(
            home: Scaffold(
              body: MediaAnnotationSettingsPage(
                configStore: store,
                contentConfigStore: contentStore,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(MediaAnnotationSettingsPage.audioTranscribeSwitchKey),
    );
    await tester.pumpAndSettle();

    expect(contentStore.writes, isNotEmpty);
    expect(contentStore.writes.last.audioTranscribeEnabled, isTrue);
  });
}

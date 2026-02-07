import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/content_enrichment/content_enrichment_config_store.dart';
import 'package:secondloop/core/content_enrichment/linux_ocr_model_store.dart';
import 'package:secondloop/core/content_enrichment/linux_pdf_compress_resource_store.dart';
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

final class _FakeLinuxOcrModelStore implements LinuxOcrModelStore {
  _FakeLinuxOcrModelStore({
    required this.status,
    this.downloadResult,
    this.onDownload,
  });

  LinuxOcrModelStatus status;
  final LinuxOcrModelStatus? downloadResult;
  final Future<LinuxOcrModelStatus> Function()? onDownload;
  int downloadCalls = 0;
  int deleteCalls = 0;

  @override
  Future<LinuxOcrModelStatus> readStatus() async => status;

  @override
  Future<LinuxOcrModelStatus> downloadModels() async {
    downloadCalls += 1;
    if (onDownload != null) {
      status = await onDownload!();
      return status;
    }
    status = downloadResult ??
        const LinuxOcrModelStatus(
          supported: true,
          installed: true,
          modelDirPath: '/tmp/secondloop-ocr-models',
          modelCount: 3,
          totalBytes: 1024,
          source: LinuxOcrModelSource.downloaded,
        );
    return status;
  }

  @override
  Future<LinuxOcrModelStatus> deleteModels() async {
    deleteCalls += 1;
    status = const LinuxOcrModelStatus(
      supported: true,
      installed: false,
      modelDirPath: null,
      modelCount: 0,
      totalBytes: 0,
      source: LinuxOcrModelSource.none,
    );
    return status;
  }

  @override
  Future<String?> readInstalledModelDir() async => status.modelDirPath;
}

final class _FakeLinuxPdfCompressResourceStore
    implements LinuxPdfCompressResourceStore {
  _FakeLinuxPdfCompressResourceStore({
    required this.status,
  });

  LinuxPdfCompressResourceStatus status;
  int downloadCalls = 0;
  int deleteCalls = 0;

  @override
  Future<LinuxPdfCompressResourceStatus> readStatus() async => status;

  @override
  Future<LinuxPdfCompressResourceStatus> downloadResources() async {
    downloadCalls += 1;
    status = const LinuxPdfCompressResourceStatus(
      supported: true,
      installed: true,
      resourceDirPath: '/tmp/secondloop-pdf-compress-resource',
      fileCount: 2,
      totalBytes: 2048,
      source: LinuxPdfCompressResourceSource.downloaded,
    );
    return status;
  }

  @override
  Future<LinuxPdfCompressResourceStatus> deleteResources() async {
    deleteCalls += 1;
    status = const LinuxPdfCompressResourceStatus(
      supported: true,
      installed: false,
      resourceDirPath: null,
      fileCount: 0,
      totalBytes: 0,
      source: LinuxPdfCompressResourceSource.none,
    );
    return status;
  }

  @override
  Future<String?> readInstalledResourceDir() async => status.resourceDirPath;
}

ContentEnrichmentConfig _defaultContentConfig() {
  return const ContentEnrichmentConfig(
    urlFetchEnabled: true,
    documentExtractEnabled: true,
    documentKeepOriginalMaxBytes: 104857600,
    pdfSmartCompressEnabled: true,
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

    final scrollable = find.byType(Scrollable).first;
    final audioSwitch =
        find.byKey(MediaAnnotationSettingsPage.audioTranscribeSwitchKey);
    await tester.scrollUntilVisible(
      audioSwitch,
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(audioSwitch, findsOneWidget);

    final annotateSwitch =
        find.byKey(MediaAnnotationSettingsPage.annotateSwitchKey);
    await tester.scrollUntilVisible(
      annotateSwitch,
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(annotateSwitch, findsOneWidget);

    final searchSwitch =
        find.byKey(MediaAnnotationSettingsPage.searchSwitchKey);
    await tester.scrollUntilVisible(
      searchSwitch,
      150,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(searchSwitch, findsOneWidget);
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
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      searchSwitch,
      300,
      scrollable: scrollable,
    );
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

  testWidgets('PDF settings keep only smart compression switch',
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

    final scrollable = find.byType(Scrollable).first;
    final pdfSwitch =
        find.byKey(MediaAnnotationSettingsPage.pdfCompressSwitchKey);
    await tester.scrollUntilVisible(
      pdfSwitch,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(pdfSwitch, findsOneWidget);
    expect(find.text('Compression profile'), findsNothing);
    expect(find.text('压缩档位'), findsNothing);
  });

  testWidgets('Document OCR hides advanced language and page controls',
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

    final scrollable = find.byType(Scrollable).first;
    final ocrSwitch = find.byKey(MediaAnnotationSettingsPage.ocrSwitchKey);
    await tester.scrollUntilVisible(
      ocrSwitch,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(ocrSwitch, findsOneWidget);
    expect(find.text('Language hints'), findsNothing);
    expect(find.text('Auto OCR page limit'), findsNothing);
    expect(find.text('OCR DPI'), findsNothing);
    expect(find.text('语言提示'), findsNothing);
    expect(find.text('自动 OCR 页数上限'), findsNothing);
  });

  testWidgets('Linux OCR model tile shows quality warning when not installed',
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
    final linuxModelStore = _FakeLinuxOcrModelStore(
      status: const LinuxOcrModelStatus(
        supported: true,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      ),
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
                linuxOcrModelStore: linuxModelStore,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final warningKey = find.byKey(
      const ValueKey('media_annotation_settings_linux_ocr_quality_warning'),
    );
    await tester.scrollUntilVisible(
      warningKey,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(warningKey, findsOneWidget);
  });

  testWidgets('Linux OCR download shows progress bar while downloading',
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
    final completer = Completer<LinuxOcrModelStatus>();
    final linuxModelStore = _FakeLinuxOcrModelStore(
      status: const LinuxOcrModelStatus(
        supported: true,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      ),
      onDownload: () => completer.future,
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
                linuxOcrModelStore: linuxModelStore,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final downloadButton =
        find.byKey(MediaAnnotationSettingsPage.linuxOcrModelDownloadButtonKey);
    await tester.scrollUntilVisible(
      downloadButton,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(downloadButton);
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey('media_annotation_settings_linux_ocr_download_progress'),
      ),
      findsOneWidget,
    );

    completer.complete(const LinuxOcrModelStatus(
      supported: true,
      installed: true,
      modelDirPath: '/tmp/secondloop-ocr-models',
      modelCount: 3,
      totalBytes: 1024,
      source: LinuxOcrModelSource.downloaded,
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('Linux OCR models can be downloaded and removed from settings',
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
    final linuxModelStore = _FakeLinuxOcrModelStore(
      status: const LinuxOcrModelStatus(
        supported: true,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      ),
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
                linuxOcrModelStore: linuxModelStore,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final downloadButton =
        find.byKey(MediaAnnotationSettingsPage.linuxOcrModelDownloadButtonKey);
    await tester.scrollUntilVisible(
      downloadButton,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(downloadButton, findsOneWidget);

    await tester.tap(downloadButton);
    await tester.pumpAndSettle();
    expect(linuxModelStore.downloadCalls, 1);

    final deleteButton =
        find.byKey(MediaAnnotationSettingsPage.linuxOcrModelDeleteButtonKey);
    expect(deleteButton, findsOneWidget);

    await tester.scrollUntilVisible(
      deleteButton,
      120,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(linuxModelStore.deleteCalls, 1);
  });

  testWidgets('Linux OCR models show runtime missing hint after download',
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
    final linuxModelStore = _FakeLinuxOcrModelStore(
      status: const LinuxOcrModelStatus(
        supported: true,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      ),
      downloadResult: const LinuxOcrModelStatus(
        supported: true,
        installed: false,
        modelDirPath: null,
        modelCount: 3,
        totalBytes: 1024,
        source: LinuxOcrModelSource.none,
        message: 'runtime_missing:linux_ocr_runtime_exec_not_permitted',
      ),
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
                linuxOcrModelStore: linuxModelStore,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final downloadButton =
        find.byKey(MediaAnnotationSettingsPage.linuxOcrModelDownloadButtonKey);
    await tester.scrollUntilVisible(
      downloadButton,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(downloadButton);
    await tester.pumpAndSettle();

    expect(linuxModelStore.downloadCalls, 1);
    expect(
      find.textContaining(
          'Models are downloaded, but OCR runtime is not ready'),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.textContaining('linux_ocr_runtime_exec_not_permitted'),
      findsAtLeastNWidgets(1),
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
      'Linux PDF compression resources can be downloaded and removed from settings',
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
    final linuxPdfStore = _FakeLinuxPdfCompressResourceStore(
      status: const LinuxPdfCompressResourceStatus(
        supported: true,
        installed: false,
        resourceDirPath: null,
        fileCount: 0,
        totalBytes: 0,
        source: LinuxPdfCompressResourceSource.none,
      ),
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
                linuxPdfCompressResourceStore: linuxPdfStore,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final downloadButton = find.byKey(
      MediaAnnotationSettingsPage.linuxPdfCompressResourceDownloadButtonKey,
    );
    await tester.scrollUntilVisible(
      downloadButton,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(downloadButton, findsOneWidget);

    await tester.tap(downloadButton);
    await tester.pumpAndSettle();
    expect(linuxPdfStore.downloadCalls, 1);

    final deleteButton = find.byKey(
      MediaAnnotationSettingsPage.linuxPdfCompressResourceDeleteButtonKey,
    );
    expect(deleteButton, findsOneWidget);

    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(linuxPdfStore.deleteCalls, 1);
  });
}

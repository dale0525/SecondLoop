import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/content_enrichment/content_enrichment_config_store.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/content_enrichment/linux_ocr_model_store.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/ai/media_source_prefs.dart';
import 'package:secondloop/core/media_annotation/media_annotation_config_store.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/settings/media_annotation_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';
import 'test_backend.dart';

part 'media_annotation_settings_smoke_ocr_cases.dart';

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

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _MixedProfilesBackend extends TestAppBackend {
  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[
        LlmProfile(
          id: 'p1',
          name: 'OpenAI',
          providerType: 'openai-compatible',
          baseUrl: 'https://api.openai.com/v1',
          modelName: 'gpt-4o-mini',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        LlmProfile(
          id: 'p2',
          name: 'Gemini',
          providerType: 'gemini',
          baseUrl: 'https://generativelanguage.googleapis.com',
          modelName: 'gemini-2.0-flash',
          isActive: false,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ];
}

MediaAnnotationConfig _defaultMediaConfig({
  bool mediaUnderstandingEnabled = true,
  String providerMode = 'follow_ask_ai',
}) {
  return MediaAnnotationConfig(
    annotateEnabled: mediaUnderstandingEnabled,
    searchEnabled: mediaUnderstandingEnabled,
    allowCellular: false,
    providerMode: providerMode,
  );
}

ContentEnrichmentConfig _defaultContentConfig({
  bool mediaUnderstandingEnabled = true,
}) {
  return ContentEnrichmentConfig(
    urlFetchEnabled: true,
    documentExtractEnabled: true,
    documentKeepOriginalMaxBytes: 104857600,
    audioTranscribeEnabled: mediaUnderstandingEnabled,
    audioTranscribeEngine: 'whisper',
    videoExtractEnabled: true,
    videoProxyEnabled: true,
    videoProxyMaxDurationMs: 600000,
    videoProxyMaxBytes: 209715200,
    ocrEnabled: mediaUnderstandingEnabled,
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

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeMediaAnnotationConfigStore store,
  required _FakeContentEnrichmentConfigStore contentStore,
  LinuxOcrModelStore? linuxOcrModelStore,
  SubscriptionStatus subscriptionStatus = SubscriptionStatus.unknown,
  CloudAuthController? cloudAuthController,
  String cloudGatewayBaseUrl = 'https://gateway.test',
  AppBackend? backend,
  bool embedded = false,
}) async {
  Widget page = MediaAnnotationSettingsPage(
    configStore: store,
    contentConfigStore: contentStore,
    linuxOcrModelStore: linuxOcrModelStore,
    embedded: embedded,
  );
  if (embedded) {
    page = SingleChildScrollView(child: page);
  }

  Widget home = SubscriptionScope(
    controller: _FakeSubscriptionController(subscriptionStatus),
    child: Scaffold(body: page),
  );
  if (backend != null) {
    home = AppBackendScope(
      backend: backend,
      child: home,
    );
  }
  if (cloudAuthController != null) {
    home = CloudAuthScope(
      controller: cloudAuthController,
      gatewayConfig: CloudGatewayConfig(
        baseUrl: cloudGatewayBaseUrl,
        modelName: 'cloud',
      ),
      child: home,
    );
  }

  await tester.pumpWidget(
    SessionScope(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      lock: () {},
      child: wrapWithI18n(
        MaterialApp(
          home: home,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _wifiSwitchValue(WidgetTester tester, Finder finder) {
  return tester.widget<SwitchListTile>(finder).value;
}

bool _sourceRadioSelected(WidgetTester tester, Finder finder) {
  final tile = tester.widget<RadioListTile<MediaSourcePreference>>(finder);
  return tile.value == tile.groupValue;
}

void main() {
  testWidgets('Media understanding settings shows one master switch only',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
    );

    expect(
      find.byKey(MediaAnnotationSettingsPage.mediaUnderstandingSwitchKey),
      findsOneWidget,
    );
    expect(
      find.byKey(MediaAnnotationSettingsPage.audioTranscribeSwitchKey),
      findsNothing,
    );
    expect(
      find.byKey(MediaAnnotationSettingsPage.ocrSwitchKey),
      findsNothing,
    );
    expect(
      find.byKey(MediaAnnotationSettingsPage.annotateSwitchKey),
      findsNothing,
    );
    expect(
      find.byKey(MediaAnnotationSettingsPage.searchSwitchKey),
      findsNothing,
    );
  });

  testWidgets('Routing guide text is removed from media settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
    );

    expect(find.text('Choose your AI source'), findsNothing);
    expect(find.text('先选择 AI 来源'), findsNothing);
  });

  _registerOcrModeTests();

  testWidgets('Turning off media understanding hides detailed settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
    );

    final masterSwitch =
        find.byKey(MediaAnnotationSettingsPage.mediaUnderstandingSwitchKey);
    await tester.tap(masterSwitch);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(store.writes, isNotEmpty);
    expect(contentStore.writes, isNotEmpty);
    expect(store.writes.last.annotateEnabled, isFalse);
    expect(store.writes.last.searchEnabled, isFalse);
    expect(contentStore.writes.last.audioTranscribeEnabled, isFalse);
    expect(contentStore.writes.last.ocrEnabled, isFalse);
    expect(
      find.byKey(MediaAnnotationSettingsPage.wifiOnlySwitchKey),
      findsNothing,
    );
    expect(find.text('Audio transcription'), findsNothing);
    expect(find.text('Image caption provider'), findsNothing);
  });

  testWidgets('Turning on media understanding enables all media flags',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: false),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: false),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
    );

    final masterSwitch =
        find.byKey(MediaAnnotationSettingsPage.mediaUnderstandingSwitchKey);
    await tester.tap(masterSwitch);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(store.writes, isNotEmpty);
    expect(contentStore.writes, isNotEmpty);
    expect(store.writes.last.annotateEnabled, isTrue);
    expect(store.writes.last.searchEnabled, isTrue);
    expect(contentStore.writes.last.audioTranscribeEnabled, isTrue);
    expect(contentStore.writes.last.ocrEnabled, isTrue);
  });

  testWidgets('Pro users see Use SecondLoop Cloud switch', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      subscriptionStatus: SubscriptionStatus.entitled,
    );

    expect(
      find.byKey(MediaAnnotationSettingsPage.useSecondLoopCloudSwitchKey),
      findsOneWidget,
    );
  });

  testWidgets('API profile defaults to Follow Ask AI before user override',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      backend: TestAppBackend(),
    );

    final scrollable = find.byType(Scrollable).first;
    final audioApiTile =
        find.byKey(MediaAnnotationSettingsPage.audioApiProfileTileKey);
    await tester.scrollUntilVisible(
      audioApiTile,
      220,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: audioApiTile, matching: find.text('Follow Ask AI')),
      findsOneWidget,
    );

    final imageApiTile =
        find.byKey(MediaAnnotationSettingsPage.imageApiProfileTileKey);
    await tester.scrollUntilVisible(
      imageApiTile,
      240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: imageApiTile, matching: find.text('Follow Ask AI')),
      findsOneWidget,
    );
  });

  testWidgets('Wi-Fi only switch acts as media understanding master control',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      subscriptionStatus: SubscriptionStatus.notEntitled,
    );

    final wifiOnlySwitch =
        find.byKey(MediaAnnotationSettingsPage.wifiOnlySwitchKey);
    expect(wifiOnlySwitch, findsOneWidget);

    await tester.tap(wifiOnlySwitch);
    await tester.pumpAndSettle();
    expect(store.writes, isNotEmpty);
    expect(store.writes.last.allowCellular, isTrue);

    await tester.tap(wifiOnlySwitch);
    await tester.pumpAndSettle();
    expect(store.writes.last.allowCellular, isFalse);
  });

  testWidgets('Embedded audio/OCR Wi-Fi toggles are independent',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );
    final linuxModelStore = _FakeLinuxOcrModelStore(
      status: const LinuxOcrModelStatus(
        supported: false,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      ),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
      embedded: true,
    );

    final audioWifiSwitch =
        find.byKey(MediaAnnotationSettingsPage.audioWifiOnlySwitchKey);
    final ocrWifiSwitch =
        find.byKey(MediaAnnotationSettingsPage.ocrWifiOnlySwitchKey);

    expect(audioWifiSwitch, findsOneWidget);
    expect(ocrWifiSwitch, findsOneWidget);
    expect(
      find.byKey(MediaAnnotationSettingsPage.imageWifiOnlySwitchKey),
      findsNothing,
    );

    expect(_wifiSwitchValue(tester, audioWifiSwitch), isTrue);
    expect(_wifiSwitchValue(tester, ocrWifiSwitch), isTrue);

    await tester.tap(audioWifiSwitch);
    await tester.pumpAndSettle();

    expect(_wifiSwitchValue(tester, audioWifiSwitch), isFalse);
    expect(_wifiSwitchValue(tester, ocrWifiSwitch), isTrue);

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
      embedded: true,
    );

    expect(_wifiSwitchValue(tester, audioWifiSwitch), isFalse);
    expect(_wifiSwitchValue(tester, ocrWifiSwitch), isTrue);
  });

  testWidgets('Embedded audio/OCR source radios default to auto',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );
    final linuxModelStore = _FakeLinuxOcrModelStore(
      status: const LinuxOcrModelStatus(
        supported: false,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      ),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
      embedded: true,
    );

    final audioAuto =
        find.byKey(const ValueKey('media_annotation_settings_audio_mode_auto'));
    final ocrAuto =
        find.byKey(const ValueKey('media_annotation_settings_ocr_mode_auto'));

    expect(audioAuto, findsOneWidget);
    expect(ocrAuto, findsOneWidget);
    expect(_sourceRadioSelected(tester, audioAuto), isTrue);
    expect(_sourceRadioSelected(tester, ocrAuto), isTrue);

    expect(
      find.byKey(const ValueKey('media_annotation_settings_audio_card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('media_annotation_settings_ocr_card')),
      findsOneWidget,
    );
    expect(find.text('Description & route'), findsNothing);
    expect(
      find.byKey(
          const ValueKey('media_annotation_settings_audio_open_api_keys')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('media_annotation_settings_ocr_open_api_keys')),
      findsOneWidget,
    );

    final audioByok =
        find.byKey(const ValueKey('media_annotation_settings_audio_mode_byok'));
    await tester.tap(audioByok);
    await tester.pumpAndSettle();

    expect(_sourceRadioSelected(tester, audioByok), isTrue);
    expect(find.text('Transcription engine'), findsOneWidget);
  });

  testWidgets(
      'Audio transcribe API profile picker supports Follow Ask AI and filters to OpenAI-compatible profiles',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      subscriptionStatus: SubscriptionStatus.entitled,
      backend: _MixedProfilesBackend(),
    );

    final scrollable = find.byType(Scrollable).first;
    final configureApiTile =
        find.byKey(MediaAnnotationSettingsPage.audioApiProfileTileKey);
    await tester.scrollUntilVisible(
      configureApiTile,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(configureApiTile);
    await tester.pumpAndSettle();

    final dialog = find.byType(SimpleDialog);
    expect(find.text('Open Cloud account'), findsNothing);
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('SecondLoop Cloud'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Follow Ask AI')),
      findsOneWidget,
    );
    expect(find.descendant(of: dialog, matching: find.text('OpenAI')),
        findsOneWidget);
    expect(find.text('Gemini'), findsNothing);
  });
  testWidgets(
      'Audio transcribe local runtime mode disables profile override picker',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      backend: TestAppBackend(),
    );

    final scrollable = find.byType(Scrollable).first;
    final engineTile = find.widgetWithText(ListTile, 'Transcription engine');
    await tester.scrollUntilVisible(
      engineTile,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(engineTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local runtime').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(contentStore.writes, isNotEmpty);
    expect(contentStore.writes.last.audioTranscribeEngine, 'local_runtime');

    final audioApiTile =
        find.byKey(MediaAnnotationSettingsPage.audioApiProfileTileKey);
    expect(
      find.descendant(of: audioApiTile, matching: find.text('Local mode')),
      findsOneWidget,
    );

    await tester.tap(audioApiTile);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets('Non-Pro users do not see Use SecondLoop Cloud switch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      subscriptionStatus: SubscriptionStatus.notEntitled,
    );

    expect(
      find.byKey(MediaAnnotationSettingsPage.useSecondLoopCloudSwitchKey),
      findsNothing,
    );
  });

  testWidgets(
      'Audio transcribe API profile can be selected from existing profiles',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      backend: TestAppBackend(),
    );

    final scrollable = find.byType(Scrollable).first;
    final audioApiTile =
        find.byKey(MediaAnnotationSettingsPage.audioApiProfileTileKey);
    await tester.scrollUntilVisible(
      audioApiTile,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(audioApiTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();

    expect(store.writes, isNotEmpty);
    expect(store.writes.last.byokProfileId, 'p1');
    expect(store.writes.last.providerMode, 'byok_profile');
  });

  testWidgets(
      'Image caption API profile can be selected from existing profiles',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      backend: TestAppBackend(),
    );

    final scrollable = find.byType(Scrollable).first;
    final imageApiTile =
        find.byKey(MediaAnnotationSettingsPage.imageApiProfileTileKey);
    await tester.scrollUntilVisible(
      imageApiTile,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(imageApiTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();

    expect(store.writes, isNotEmpty);
    expect(store.writes.last.byokProfileId, 'p1');
    expect(store.writes.last.providerMode, 'byok_profile');
  });

  testWidgets('Linux OCR runtime tile is visible when runtime is not installed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
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

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
    );

    final scrollable = find.byType(Scrollable).first;
    final runtimeTile =
        find.byKey(MediaAnnotationSettingsPage.linuxOcrModelTileKey);
    await tester.scrollUntilVisible(
      runtimeTile,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(runtimeTile, findsOneWidget);
  });

  testWidgets('Local capability engine card uses unified capability layout',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
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

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
    );

    final scrollable = find.byType(Scrollable).first;
    final runtimeTile =
        find.byKey(MediaAnnotationSettingsPage.linuxOcrModelTileKey);
    await tester.scrollUntilVisible(
      runtimeTile,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(runtimeTile, findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
            'media_annotation_settings_local_capability_status_tile'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'Audio runtime tile stays visible when runtime status is unavailable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );
    final linuxModelStore = _FakeLinuxOcrModelStore(
      status: const LinuxOcrModelStatus(
        supported: false,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      ),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
    );

    final scrollable = find.byType(Scrollable).first;
    final runtimeTile =
        find.byKey(MediaAnnotationSettingsPage.linuxOcrModelTileKey);
    await tester.scrollUntilVisible(
      runtimeTile,
      260,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(runtimeTile, findsOneWidget);
    expect(find.textContaining('runtime'), findsWidgets);
  });

  testWidgets('Linux OCR download shows progress bar while downloading',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
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

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
    );

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
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
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

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
    );

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
    await tester.tap(find.widgetWithText(FilledButton, 'Clear Runtime'));
    await tester.pumpAndSettle();
    expect(linuxModelStore.deleteCalls, 1);
  });

  testWidgets('Linux OCR models show runtime missing hint after download',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
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

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
    );

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
    expect(find.textContaining('Runtime missing'), findsAtLeastNWidgets(1));
    expect(
      find.textContaining('linux_ocr_runtime_exec_not_permitted'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('Linux OCR models map runtime payload code to user-friendly text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
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
        modelCount: 1,
        totalBytes: 114,
        source: LinuxOcrModelSource.none,
        message: 'runtime_payload_incomplete',
      ),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      linuxOcrModelStore: linuxModelStore,
    );

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
      find.textContaining('Runtime files are incomplete'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('runtime_payload_incomplete'), findsNothing);
  });
}

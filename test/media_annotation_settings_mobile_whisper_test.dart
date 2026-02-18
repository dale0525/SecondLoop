import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/ai/audio_transcribe_whisper_model_prefs.dart';
import 'package:secondloop/core/ai/audio_transcribe_whisper_model_store.dart';
import 'package:secondloop/core/content_enrichment/content_enrichment_config_store.dart';
import 'package:secondloop/core/content_enrichment/linux_ocr_model_store.dart';
import 'package:secondloop/core/media_annotation/media_annotation_config_store.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/settings/media_annotation_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

final class _FakeMediaAnnotationConfigStore
    implements MediaAnnotationConfigStore {
  _FakeMediaAnnotationConfigStore(this._config);

  MediaAnnotationConfig _config;

  @override
  Future<MediaAnnotationConfig> read(Uint8List key) async => _config;

  @override
  Future<void> write(Uint8List key, MediaAnnotationConfig config) async {
    _config = config;
  }
}

final class _FakeContentEnrichmentConfigStore
    implements ContentEnrichmentConfigStore {
  _FakeContentEnrichmentConfigStore(this._config);

  ContentEnrichmentConfig _config;

  @override
  Future<ContentEnrichmentConfig> readContentEnrichment(Uint8List key) async =>
      _config;

  @override
  Future<void> writeContentEnrichment(
    Uint8List key,
    ContentEnrichmentConfig config,
  ) async {
    _config = config;
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
  @override
  Future<LinuxOcrModelStatus> readStatus() async {
    return const LinuxOcrModelStatus(
      supported: false,
      installed: false,
      modelDirPath: null,
      modelCount: 0,
      totalBytes: 0,
      source: LinuxOcrModelSource.none,
    );
  }

  @override
  Future<LinuxOcrModelStatus> downloadModels() {
    throw UnimplementedError();
  }

  @override
  Future<LinuxOcrModelStatus> deleteModels() {
    throw UnimplementedError();
  }

  @override
  Future<String?> readInstalledModelDir() async => null;
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  @override
  SubscriptionStatus get status => SubscriptionStatus.unknown;
}

final class _SpyAudioWhisperModelStore
    implements AudioTranscribeWhisperModelStore {
  _SpyAudioWhisperModelStore({
    required this.supportsRuntimeDownload,
  });

  @override
  final bool supportsRuntimeDownload;

  int ensureCalls = 0;

  @override
  Future<bool> isModelAvailable({required String model}) async => false;

  @override
  Future<AudioWhisperModelEnsureResult> ensureModelAvailable({
    required String model,
    void Function(AudioWhisperModelDownloadProgress progress)? onProgress,
  }) async {
    ensureCalls += 1;
    return AudioWhisperModelEnsureResult(
      model: model,
      status: AudioWhisperModelEnsureStatus.alreadyAvailable,
      path: '/tmp/$model.bin',
    );
  }
}

MediaAnnotationConfig _defaultMediaConfig() {
  return const MediaAnnotationConfig(
    annotateEnabled: true,
    searchEnabled: true,
    allowCellular: false,
    providerMode: 'follow_ask_ai',
  );
}

ContentEnrichmentConfig _defaultContentConfig() {
  return const ContentEnrichmentConfig(
    urlFetchEnabled: true,
    documentExtractEnabled: true,
    documentKeepOriginalMaxBytes: 104857600,
    audioTranscribeEnabled: true,
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

Future<void> _pumpPage(
  WidgetTester tester, {
  required AudioTranscribeWhisperModelStore audioStore,
}) async {
  final mediaStore = _FakeMediaAnnotationConfigStore(_defaultMediaConfig());
  final contentStore =
      _FakeContentEnrichmentConfigStore(_defaultContentConfig());

  Widget page = MediaAnnotationSettingsPage(
    embedded: true,
    configStore: mediaStore,
    contentConfigStore: contentStore,
    linuxOcrModelStore: _FakeLinuxOcrModelStore(),
    audioWhisperModelStore: audioStore,
  );
  page = SingleChildScrollView(child: page);

  await tester.pumpWidget(
    SessionScope(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      lock: () {},
      child: wrapWithI18n(
        MaterialApp(
          home: SubscriptionScope(
            controller: _FakeSubscriptionController(),
            child: Scaffold(
              body: page,
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

Future<void> _pickWhisperModel(
  WidgetTester tester, {
  required String modelValue,
}) async {
  final tile = find.byKey(
      const ValueKey('media_annotation_settings_audio_whisper_model_tile'));
  await tester.scrollUntilVisible(
    tile,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();

  await tester.tap(tile);
  await tester.pumpAndSettle();

  final option = find.byWidgetPredicate(
    (widget) => widget is RadioListTile<String> && widget.value == modelValue,
  );
  await tester.tap(option.first);
  await tester.pumpAndSettle();

  final dialogSaveButton = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(FilledButton),
  );
  await tester.tap(dialogSaveButton.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'mobile platform switches whisper model without downloading desktop runtime files',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final audioStore = _SpyAudioWhisperModelStore(
        supportsRuntimeDownload: true,
      );

      await _pumpPage(
        tester,
        audioStore: audioStore,
      );

      await _pickWhisperModel(
        tester,
        modelValue: 'small',
      );

      expect(audioStore.ensureCalls, 0);
      expect(await AudioTranscribeWhisperModelPrefs.read(), 'small');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'desktop platform keeps whisper model runtime download behavior',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final audioStore = _SpyAudioWhisperModelStore(
        supportsRuntimeDownload: true,
      );

      await _pumpPage(
        tester,
        audioStore: audioStore,
      );

      await _pickWhisperModel(
        tester,
        modelValue: 'small',
      );

      expect(audioStore.ensureCalls, 1);
      expect(await AudioTranscribeWhisperModelPrefs.read(), 'small');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );
}

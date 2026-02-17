import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/audio_transcribe_whisper_model_store.dart';
import 'package:secondloop/core/ai/audio_transcribe_whisper_model_store_io.dart';

void main() {
  group('FileSystemAudioTranscribeWhisperModelStore', () {
    test('downloads missing model into runtime whisper directory', () async {
      final appDir = await Directory.systemTemp.createTemp(
        'audio_whisper_store_download_',
      );
      addTearDown(() async {
        if (await appDir.exists()) {
          await appDir.delete(recursive: true);
        }
      });

      final progressEvents = <AudioWhisperModelDownloadProgress>[];
      var downloadCalls = 0;

      final store = FileSystemAudioTranscribeWhisperModelStore(
        appDirProvider: () async => appDir.path,
        whisperBaseUrl: 'https://example.com/models',
        downloadFile: ({
          required Uri url,
          required File destinationFile,
          required void Function(int receivedBytes, int? totalBytes) onProgress,
        }) async {
          downloadCalls += 1;
          expect(url.toString(),
              'https://example.com/models/ggml-large-v3-turbo.bin');
          onProgress(64, 128);
          onProgress(128, 128);
          await destinationFile.writeAsBytes(List<int>.filled(128, 1),
              flush: true);
        },
      );

      final result = await store.ensureModelAvailable(
        model: 'large-v3-turbo',
        onProgress: progressEvents.add,
      );

      final expectedModelFile = File(
        '${appDir.path}/ocr/desktop/runtime/whisper/ggml-large-v3-turbo.bin',
      );

      expect(result.status, AudioWhisperModelEnsureStatus.downloaded);
      expect(downloadCalls, 1);
      expect(await expectedModelFile.exists(), isTrue);
      expect(progressEvents, isNotEmpty);
      expect(progressEvents.last.receivedBytes, 128);
      expect(progressEvents.last.totalBytes, 128);
    });

    test('retries download and keeps final model file', () async {
      final appDir = await Directory.systemTemp.createTemp(
        'audio_whisper_store_retry_',
      );
      addTearDown(() async {
        if (await appDir.exists()) {
          await appDir.delete(recursive: true);
        }
      });

      var callCount = 0;
      final store = FileSystemAudioTranscribeWhisperModelStore(
        appDirProvider: () async => appDir.path,
        whisperBaseUrl: 'https://example.com/models',
        retryDelays: const <Duration>[Duration.zero, Duration.zero],
        downloadFile: ({
          required Uri url,
          required File destinationFile,
          required void Function(int receivedBytes, int? totalBytes) onProgress,
        }) async {
          callCount += 1;
          if (callCount == 1) {
            throw const HttpException('network failed');
          }
          onProgress(10, 10);
          await destinationFile.writeAsBytes(List<int>.filled(10, 7),
              flush: true);
        },
      );

      final result = await store.ensureModelAvailable(model: 'small');

      final expectedModelFile =
          File('${appDir.path}/ocr/desktop/runtime/whisper/ggml-small.bin');
      expect(result.status, AudioWhisperModelEnsureStatus.downloaded);
      expect(callCount, 2);
      expect(await expectedModelFile.exists(), isTrue);
      expect(await expectedModelFile.length(), 10);
    });

    test('returns alreadyAvailable when file already exists', () async {
      final appDir = await Directory.systemTemp.createTemp(
        'audio_whisper_store_existing_',
      );
      addTearDown(() async {
        if (await appDir.exists()) {
          await appDir.delete(recursive: true);
        }
      });

      final whisperDir =
          Directory('${appDir.path}/ocr/desktop/runtime/whisper');
      await whisperDir.create(recursive: true);
      final existing = File('${whisperDir.path}/ggml-base.bin');
      await existing.writeAsBytes(List<int>.filled(32, 9), flush: true);

      var downloadCalls = 0;
      final store = FileSystemAudioTranscribeWhisperModelStore(
        appDirProvider: () async => appDir.path,
        downloadFile: ({
          required Uri url,
          required File destinationFile,
          required void Function(int receivedBytes, int? totalBytes) onProgress,
        }) async {
          downloadCalls += 1;
          await destinationFile.writeAsBytes(const <int>[1], flush: true);
        },
      );

      final result = await store.ensureModelAvailable(model: 'base');

      expect(result.status, AudioWhisperModelEnsureStatus.alreadyAvailable);
      expect(downloadCalls, 0);
      expect(await existing.length(), 32);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_runner.dart';

void main() {
  tearDown(() {
    resetObservedGatewayMaxAudioBytesForTest();
  });

  test('cloud clients use default maxInputBytes when no header observed', () {
    final whisper = CloudGatewayWhisperAudioTranscribeClient(
      gatewayBaseUrl: 'https://gateway.test',
      idToken: 'token',
    );
    final multimodal = CloudGatewayMultimodalAudioTranscribeClient(
      gatewayBaseUrl: 'https://gateway.test',
      idToken: 'token',
    );

    expect(whisper.maxInputBytes, 15360000);
    expect(multimodal.maxInputBytes, 15360000);
  });

  test('loads persisted gateway max bytes before selecting cloud clients',
      () async {
    configureGatewayMaxAudioBytesPersistenceForTest(
      read: () async => 2048,
      write: (_) async {},
    );

    await ensureGatewayMaxAudioBytesLoadedForTest();

    final whisper = CloudGatewayWhisperAudioTranscribeClient(
      gatewayBaseUrl: 'https://gateway.test',
      idToken: 'token',
    );
    final multimodal = CloudGatewayMultimodalAudioTranscribeClient(
      gatewayBaseUrl: 'https://gateway.test',
      idToken: 'token',
    );

    expect(whisper.maxInputBytes, 2048);
    expect(multimodal.maxInputBytes, 2048);
  });

  test('observed gateway header updates cache and persists value', () async {
    int? persistedValue;
    configureGatewayMaxAudioBytesPersistenceForTest(
      read: () async => null,
      write: (value) async {
        persistedValue = value;
      },
    );

    observeGatewayMaxAudioBytesHeaderForTest('8192');
    await Future<void>.delayed(Duration.zero);

    final whisper = CloudGatewayWhisperAudioTranscribeClient(
      gatewayBaseUrl: 'https://gateway.test',
      idToken: 'token',
    );

    expect(whisper.maxInputBytes, 8192);
    expect(persistedValue, 8192);
  });

  test('invalid observed header keeps default maxInputBytes', () async {
    int writeCount = 0;
    configureGatewayMaxAudioBytesPersistenceForTest(
      read: () async => null,
      write: (_) async {
        writeCount += 1;
      },
    );

    observeGatewayMaxAudioBytesHeaderForTest('invalid');
    await Future<void>.delayed(Duration.zero);

    final whisper = CloudGatewayWhisperAudioTranscribeClient(
      gatewayBaseUrl: 'https://gateway.test',
      idToken: 'token',
    );

    expect(whisper.maxInputBytes, 15360000);
    expect(writeCount, 0);
  });
}

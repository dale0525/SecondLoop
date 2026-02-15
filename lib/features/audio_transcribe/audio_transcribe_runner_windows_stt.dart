part of 'audio_transcribe_runner.dart';

String? _cachedBundledFfmpegExecutablePathForAudioTranscribe;
const String _kWindowsSpeechRecognizerUnavailableError =
    'speech_recognizer_unavailable';
const String _kWindowsSpeechRecognizerLangMissingError =
    'speech_recognizer_lang_missing';
const String _kAudioTranscribeNativeSttMissingSpeechPackError =
    'audio_transcribe_native_stt_missing_speech_pack';

const String _kWindowsSpeechRecognizerProbePowerShellScript = r'''
param(
  [Parameter(Mandatory = $false)]
  [string]$Lang = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Speech

function Normalize-Lang([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) {
    return ''
  }
  $normalized = $value.Trim().Replace('_', '-').ToLowerInvariant()
  if ($normalized -eq 'auto' -or $normalized -eq 'und' -or $normalized -eq 'unknown') {
    return ''
  }
  return $normalized
}

function Find-Recognizer([System.Collections.ObjectModel.ReadOnlyCollection[System.Speech.Recognition.RecognizerInfo]]$items, [string]$lang) {
  if ([string]::IsNullOrWhiteSpace($lang)) {
    return $null
  }
  $langPrimary = $lang.Split('-')[0]
  foreach ($item in $items) {
    $cultureName = $item.Culture.Name
    if ([string]::IsNullOrWhiteSpace($cultureName)) {
      continue
    }
    $cultureLower = $cultureName.ToLowerInvariant()
    if ($cultureLower -eq $lang -or $cultureLower.StartsWith($lang + '-')) {
      return $item
    }
    $parts = $cultureLower.Split('-')
    if ($parts.Length -gt 0 -and $parts[0] -eq $langPrimary) {
      return $item
    }
  }
  return $null
}

$recognizers = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
if ($null -eq $recognizers -or $recognizers.Count -le 0) {
  Write-Output 'missing'
  exit 0
}

$normalizedLang = Normalize-Lang $Lang
if (-not [string]::IsNullOrWhiteSpace($normalizedLang)) {
  $selected = Find-Recognizer $recognizers $normalizedLang
  if ($null -eq $selected) {
    Write-Output 'missing_lang'
    exit 0
  }
}

Write-Output 'ok'
''';

const String _kWindowsNativeSttPowerShellScript = r'''
param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,

  [Parameter(Mandatory = $false)]
  [string]$Lang = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Speech

if (-not (Test-Path -LiteralPath $InputPath)) {
  throw 'audio_file_missing'
}

$recognizers = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
if ($null -eq $recognizers -or $recognizers.Count -le 0) {
  throw 'speech_recognizer_unavailable'
}

function Normalize-Lang([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) {
    return ''
  }
  $normalized = $value.Trim().Replace('_', '-').ToLowerInvariant()
  if ($normalized -eq 'auto' -or $normalized -eq 'und' -or $normalized -eq 'unknown') {
    return ''
  }
  return $normalized
}

function Find-Recognizer([System.Collections.ObjectModel.ReadOnlyCollection[System.Speech.Recognition.RecognizerInfo]]$items, [string]$lang) {
  if ([string]::IsNullOrWhiteSpace($lang)) {
    return $null
  }
  $langPrimary = $lang.Split('-')[0]
  foreach ($item in $items) {
    $cultureName = $item.Culture.Name
    if ([string]::IsNullOrWhiteSpace($cultureName)) {
      continue
    }
    $cultureLower = $cultureName.ToLowerInvariant()
    if ($cultureLower -eq $lang -or $cultureLower.StartsWith($lang + '-')) {
      return $item
    }
    $parts = $cultureLower.Split('-')
    if ($parts.Length -gt 0 -and $parts[0] -eq $langPrimary) {
      return $item
    }
  }
  return $null
}

$normalizedLang = Normalize-Lang $Lang
$selected = Find-Recognizer $recognizers $normalizedLang
if ($null -eq $selected) {
  if (-not [string]::IsNullOrWhiteSpace($normalizedLang)) {
    throw "speech_recognizer_lang_missing:$normalizedLang"
  }
  $selected = $recognizers | Select-Object -First 1
}

$engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine($selected.Culture)
try {
  $engine.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
  $engine.SetInputToWaveFile($InputPath)

  $parts = New-Object System.Collections.Generic.List[string]
  while ($true) {
    try {
      $result = $engine.Recognize()
    } catch [System.InvalidOperationException] {
      # Some engines throw when the wave input stream has reached terminal state.
      # Treat this as end-of-stream instead of failing the whole transcription.
      break
    }
    if ($null -eq $result) {
      break
    }
    $text = $result.Text
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      [void]$parts.Add($text.Trim())
    }
  }

  if ($parts.Count -le 0) {
    throw 'speech_transcript_empty'
  }

  $payload = @{
    text = ($parts -join ' ').Trim()
    locale = $selected.Culture.Name
  }
  Write-Output ($payload | ConvertTo-Json -Compress)
} finally {
  $engine.Dispose()
}
''';

bool isWindowsNativeSttSpeechPackMissingError(Object? error) {
  final detail = (error?.toString() ?? '').trim().toLowerCase();
  if (detail.isEmpty) return false;
  return detail.contains(_kAudioTranscribeNativeSttMissingSpeechPackError) ||
      detail.contains(_kWindowsSpeechRecognizerUnavailableError) ||
      detail.contains(_kWindowsSpeechRecognizerLangMissingError);
}

String normalizeWindowsSpeechRecognizerLang(String lang) {
  final normalized = lang.trim().replaceAll('_', '-').toLowerCase();
  if (isAutoAudioTranscribeLang(normalized)) return '';
  final parts = normalized
      .split('-')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';

  final primary = parts.first;
  if (parts.length >= 3 && parts[1].length == 4 && parts[2].length == 2) {
    return '$primary-${parts[2]}';
  }
  if (parts.length >= 2 && parts[1].length == 2) {
    return '$primary-${parts[1]}';
  }
  return primary;
}

Future<String?> _probeWindowsSpeechRecognizer({
  required String lang,
}) async {
  if (kIsWeb || !Platform.isWindows) return null;
  Directory? tempDir;
  try {
    final normalizedLang = normalizeWindowsSpeechRecognizerLang(lang);
    tempDir =
        await Directory.systemTemp.createTemp('secondloop-native-stt-probe-');
    final scriptPath = '${tempDir.path}/probe_speech.ps1';
    final scriptFile = File(scriptPath);
    await scriptFile.writeAsString(
      _kWindowsSpeechRecognizerProbePowerShellScript,
      flush: true,
    );
    final result = await Process.run(
      'powershell',
      <String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
        '-Lang',
        normalizedLang,
      ],
    );
    if (result.exitCode != 0) return null;
    final output = (result.stdout?.toString() ?? '').trim().toLowerCase();
    return output.isEmpty ? null : output;
  } catch (_) {
    return null;
  } finally {
    if (tempDir != null && await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<bool> hasWindowsSpeechRecognizerInstalled() async {
  final output = await _probeWindowsSpeechRecognizer(lang: '');
  return output == 'ok';
}

Future<bool> hasWindowsSpeechRecognizerForLang(String lang) async {
  final output = await _probeWindowsSpeechRecognizer(lang: lang);
  return output == 'ok';
}

({String sourcePath, String wavPath}) buildWindowsNativeSttTempPaths({
  required String tempDirPath,
  required String mimeType,
}) {
  final ext = CloudGatewayWhisperAudioTranscribeClient._fileExtByMimeType(
    mimeType,
  );
  return (
    sourcePath: '$tempDirPath/source.$ext',
    wavPath: '$tempDirPath/output.wav',
  );
}

final class WindowsNativeSttAudioTranscribeClient
    implements AudioTranscribeClient {
  WindowsNativeSttAudioTranscribeClient({
    this.modelName = 'windows_native_stt',
    AudioTranscribeWindowsNativeSttRequest? requestWindowsNativeSttTranscribe,
  }) : _requestWindowsNativeSttTranscribe = requestWindowsNativeSttTranscribe ??
            _requestWindowsNativeSttDefault;

  @override
  final String modelName;
  final AudioTranscribeWindowsNativeSttRequest
      _requestWindowsNativeSttTranscribe;

  @override
  String get engineName => 'native_stt';

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    if (audioBytes.isEmpty) {
      throw StateError('audio_bytes_empty');
    }

    final raw = await _requestWindowsNativeSttTranscribe(
      lang: lang,
      mimeType: mimeType,
      audioBytes: audioBytes,
    );

    final map = _decodeAudioTranscribeResponseMap(raw);
    final transcript = extractAudioTranscriptText(map);
    final duration = map['duration'];
    final durationMs = duration is num ? (duration * 1000).round() : null;
    final segments = _parseTranscriptSegments(map['segments']);

    return AudioTranscribeResponse(
      durationMs: durationMs,
      transcriptFull: transcript,
      segments: segments,
    );
  }

  static Future<String> _requestWindowsNativeSttDefault({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    if (kIsWeb || !Platform.isWindows) {
      throw StateError('audio_transcribe_native_stt_unavailable');
    }

    Directory? tempDir;
    try {
      final ffmpegPath =
          await _resolveBundledFfmpegExecutablePathForAudioTranscribe();
      if (ffmpegPath == null || ffmpegPath.trim().isEmpty) {
        throw StateError(
            'audio_transcribe_native_stt_unavailable:ffmpeg_missing');
      }

      tempDir = await Directory.systemTemp.createTemp('secondloop-native-stt-');
      final paths = buildWindowsNativeSttTempPaths(
        tempDirPath: tempDir.path,
        mimeType: mimeType,
      );
      final sourcePath = paths.sourcePath;
      final wavPath = paths.wavPath;
      final scriptPath = '${tempDir.path}/native_stt.ps1';
      final sourceFile = File(sourcePath);
      final wavFile = File(wavPath);
      final scriptFile = File(scriptPath);
      await sourceFile.writeAsBytes(audioBytes, flush: true);
      await scriptFile.writeAsString(
        _kWindowsNativeSttPowerShellScript,
        flush: true,
      );

      final ffmpegResult = await Process.run(
        ffmpegPath,
        <String>[
          '-hide_banner',
          '-loglevel',
          'error',
          '-y',
          '-i',
          sourcePath,
          '-ac',
          '1',
          '-ar',
          '16000',
          '-c:a',
          'pcm_s16le',
          wavPath,
        ],
      );
      if (ffmpegResult.exitCode != 0 || !await wavFile.exists()) {
        final ffmpegError = [
          ffmpegResult.stderr?.toString().trim() ?? '',
          ffmpegResult.stdout?.toString().trim() ?? '',
        ].where((v) => v.isNotEmpty).join(' | ');
        final detail = ffmpegError.isEmpty
            ? 'ffmpeg_exit_${ffmpegResult.exitCode}'
            : ffmpegError;
        throw StateError('audio_transcribe_native_stt_failed:$detail');
      }

      final normalizedLang = normalizeWindowsSpeechRecognizerLang(lang);
      final psResult = await Process.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptPath,
          '-InputPath',
          wavPath,
          '-Lang',
          normalizedLang,
        ],
      );

      if (psResult.exitCode != 0) {
        final errorDetail = [
          psResult.stderr?.toString().trim() ?? '',
          psResult.stdout?.toString().trim() ?? '',
        ].where((v) => v.isNotEmpty).join(' | ');
        final detail = errorDetail.isEmpty
            ? 'powershell_exit_${psResult.exitCode}'
            : errorDetail;
        if (isWindowsNativeSttSpeechPackMissingError(detail)) {
          throw StateError(_kAudioTranscribeNativeSttMissingSpeechPackError);
        }
        throw StateError('audio_transcribe_native_stt_failed:$detail');
      }

      final raw = psResult.stdout?.toString().trim() ?? '';
      if (raw.isEmpty) {
        throw StateError('audio_transcribe_native_stt_empty');
      }
      return raw;
    } catch (e) {
      if (e is StateError) rethrow;
      throw StateError('audio_transcribe_native_stt_failed:${e.toString()}');
    } finally {
      if (tempDir != null && await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}

Future<String?> _resolveBundledFfmpegExecutablePathForAudioTranscribe() async {
  final cachedPath = _cachedBundledFfmpegExecutablePathForAudioTranscribe;
  if (cachedPath != null) {
    try {
      if (await File(cachedPath).exists()) return cachedPath;
    } catch (_) {
      // ignore
    }
    _cachedBundledFfmpegExecutablePathForAudioTranscribe = null;
  }

  if (kIsWeb) return null;
  final assetPath =
      _bundledFfmpegAssetPathForCurrentPlatformForAudioTranscribe();
  if (assetPath == null) return null;

  try {
    final data = await rootBundle.load(assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (bytes.isEmpty) return null;

    final tempDir =
        Directory('${Directory.systemTemp.path}/secondloop_ffmpeg_bundle');
    await tempDir.create(recursive: true);
    final executableName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final executable = File('${tempDir.path}/$executableName');
    await executable.writeAsBytes(bytes, flush: true);

    if (!Platform.isWindows) {
      final chmodResult = await Process.run('chmod', ['755', executable.path]);
      if (chmodResult.exitCode != 0) return null;
    }

    _cachedBundledFfmpegExecutablePathForAudioTranscribe = executable.path;
    return executable.path;
  } catch (_) {
    return null;
  }
}

String? _bundledFfmpegAssetPathForCurrentPlatformForAudioTranscribe() {
  if (kIsWeb) return null;
  if (Platform.isMacOS) return 'assets/bin/ffmpeg/macos/ffmpeg';
  if (Platform.isLinux) return 'assets/bin/ffmpeg/linux/ffmpeg';
  if (Platform.isWindows) return 'assets/bin/ffmpeg/windows/ffmpeg.exe';
  return null;
}

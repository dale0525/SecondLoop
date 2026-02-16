import 'dart:typed_data';

import '../attachments/platform_pdf_ocr.dart';
import 'video_transcode_worker.dart';

part 'video_kind_classifier_rules.dart';
part 'video_kind_classifier_scoring.dart';

typedef VideoKindOcrImageFn = Future<PlatformPdfOcrResult?> Function(
  Uint8List bytes, {
  required String languageHints,
});

const String kVideoKindUnknown = 'unknown';
const String kVideoKindScreenRecording = 'screen_recording';
const String kVideoKindVlog = 'vlog';
const String kVideoKindTutorial = 'tutorial';
const String kVideoKindLecture = 'lecture';
const String kVideoKindMeeting = 'meeting';
const String kVideoKindInterview = 'interview';
const String kVideoKindGameplay = 'gameplay';
const String kVideoKindPresentation = 'presentation';

const Set<String> kCommonVideoKinds = <String>{
  kVideoKindScreenRecording,
  kVideoKindVlog,
  kVideoKindTutorial,
  kVideoKindLecture,
  kVideoKindMeeting,
  kVideoKindInterview,
  kVideoKindGameplay,
  kVideoKindPresentation,
  kVideoKindUnknown,
};

String normalizeVideoKind(
  String raw, {
  String fallback = kVideoKindUnknown,
}) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) {
    return kVideoKindUnknown;
  }

  final token = normalized.replaceAll('-', '_').replaceAll(' ', '_');
  final canonical = switch (token) {
    'screenrecording' ||
    'screen_capture' ||
    'screencapture' ||
    'screencast' ||
    'screen_record' ||
    'grabacion_de_pantalla' ||
    'grabación_de_pantalla' ||
    'enregistrement_d_ecran' ||
    "enregistrement_d'écran" ||
    'bildschirmaufnahme' ||
    'gravacao_de_tela' ||
    'gravação_de_tela' ||
    'registrazione_schermo' ||
    'запись_экрана' ||
    'تسجيل_الشاشة' ||
    'स्क्रीन_रिकॉर्डिंग' ||
    '画面録画' ||
    '画面収録' ||
    '화면_녹화' ||
    '스크린_녹화' =>
      kVideoKindScreenRecording,
    'video_blog' ||
    'daily_vlog' ||
    'diario' ||
    'tagebuch' ||
    'journal' ||
    'cotidiano' ||
    'giornata' ||
    'дневник' ||
    'يوميات' ||
    'दैनिक' ||
    '日常記録' ||
    '브이로그' =>
      kVideoKindVlog,
    'howto' ||
    'how_to' ||
    'walk_through' ||
    'walkthrough' ||
    'guia' ||
    'guía' ||
    'tutoriel' ||
    'anleitung' ||
    'passo_a_passo' ||
    'guida' ||
    'руководство' ||
    'учебник' ||
    'دليل' ||
    'ट्यूटोरियल' ||
    'मार्गदर्शिका' ||
    'チュートリアル' ||
    '튜토리얼' =>
      kVideoKindTutorial,
    'course' ||
    'lesson' ||
    'class' ||
    'seminar' ||
    'cours' ||
    'vorlesung' ||
    'leccion' ||
    'lección' ||
    'aula' ||
    'lezione' ||
    'лекция' ||
    'محاضرة' ||
    'व्याख्यान' ||
    '講義' ||
    '강의' =>
      kVideoKindLecture,
    'meeting_recording' ||
    'standup' ||
    'retro' ||
    'reunion' ||
    'reunión' ||
    'réunion' ||
    'besprechung' ||
    'sitzung' ||
    'reuniao' ||
    'reunião' ||
    'riunione' ||
    'встреча' ||
    'совещание' ||
    'اجتماع' ||
    'बैठक' ||
    '会議' ||
    '회의' ||
    'ミーティング' =>
      kVideoKindMeeting,
    'podcast' ||
    'q_and_a' ||
    'qa' ||
    'entrevista' ||
    'entretien' ||
    'vorstellungsgespräch' ||
    'vorstellungsgesprach' ||
    'bewerbungsgespräch' ||
    'bewerbungsgesprach' ||
    'colloquio' ||
    'intervista' ||
    'интервью' ||
    'собеседование' ||
    'مقابلة' ||
    'साक्षात्कार' ||
    'インタビュー' ||
    '인터뷰' =>
      kVideoKindInterview,
    'gaming' ||
    'game' ||
    'playthrough' ||
    'juego' ||
    'partida' ||
    'spiel' ||
    'jogo' ||
    'gioco' ||
    'игра' ||
    'геймплей' ||
    'لعبة' ||
    'गेमप्ले' ||
    'ゲームプレイ' ||
    '게임플레이' =>
      kVideoKindGameplay,
    'slides' ||
    'slide_deck' ||
    'keynote' ||
    'pitch_deck' ||
    'presentacion' ||
    'presentación' ||
    'présentation' ||
    'präsentation' ||
    'praesentation' ||
    'apresentacao' ||
    'apresentação' ||
    'presentazione' ||
    'презентация' ||
    'عرض_تقديمي' ||
    'प्रस्तुति' ||
    'プレゼン' ||
    '발표' =>
      kVideoKindPresentation,
    _ => token,
  };

  if (kCommonVideoKinds.contains(canonical)) {
    return canonical;
  }

  final fallbackKind = fallback.trim().toLowerCase();
  if (kCommonVideoKinds.contains(fallbackKind)) {
    return fallbackKind;
  }
  return kVideoKindUnknown;
}

String keyframeKindForVideoKind(String videoKind) {
  final normalized = normalizeVideoKind(videoKind);
  return switch (normalized) {
    kVideoKindScreenRecording ||
    kVideoKindTutorial ||
    kVideoKindLecture ||
    kVideoKindPresentation =>
      'slide',
    _ => 'scene',
  };
}

final class VideoKindClassification {
  const VideoKindClassification({
    required this.kind,
    required this.confidence,
  });

  final String kind;
  final double confidence;

  String get keyframeKind => keyframeKindForVideoKind(kind);
}

const VideoKindClassification kDefaultVideoKindClassification =
    VideoKindClassification(kind: kVideoKindVlog, confidence: 0.55);

Future<VideoKindClassification> classifyVideoKind({
  String? filename,
  required String sourceMimeType,
  Uint8List? posterBytes,
  List<VideoPreviewFrame> keyframes = const <VideoPreviewFrame>[],
  String languageHints = 'device_plus_en',
  VideoKindOcrImageFn? ocrImageFn,
}) async {
  final normalizedMime = sourceMimeType.trim().toLowerCase();
  if (!normalizedMime.startsWith('video/')) {
    return const VideoKindClassification(
      kind: kVideoKindUnknown,
      confidence: 0.0,
    );
  }

  final filenameHit = _classifyFromFilename(filename ?? '');
  if (filenameHit != null) return filenameHit;

  final samples = <Uint8List>[];
  if (posterBytes != null && posterBytes.isNotEmpty) {
    samples.add(posterBytes);
  }
  for (final frame in keyframes.take(3)) {
    if (frame.bytes.isNotEmpty) {
      samples.add(frame.bytes);
    }
  }
  if (samples.isEmpty) {
    return kDefaultVideoKindClassification;
  }

  final runOcr = ocrImageFn ?? PlatformPdfOcr.tryOcrImageBytes;
  final hints = _resolveVideoKindOcrLanguageHints(
    languageHints,
    filename ?? '',
  );

  var recognizedSamples = 0;
  var totalChars = 0;
  var maxChars = 0;
  var lowDensitySamples = 0;
  final recognizedTexts = <String>[];

  for (final sample in samples) {
    PlatformPdfOcrResult? ocr;
    try {
      ocr = await runOcr(sample, languageHints: hints);
    } catch (_) {
      ocr = null;
    }
    if (ocr == null) continue;

    final text = _normalizeWhitespace(ocr.fullText);
    final charCount = _countMeaningfulChars(text);
    if (charCount <= 0) continue;

    recognizedTexts.add(text.toLowerCase());
    recognizedSamples += 1;
    totalChars += charCount;
    if (charCount > maxChars) {
      maxChars = charCount;
    }
    if (charCount >= 18) {
      lowDensitySamples += 1;
    }
  }

  if (recognizedSamples <= 0) {
    return kDefaultVideoKindClassification;
  }

  final keywordClassification = _classifyFromOcrKeywords(recognizedTexts);
  final densityClassification = _classifyScreenRecordingFromTextDensity(
    recognizedSamples: recognizedSamples,
    totalChars: totalChars,
    maxChars: maxChars,
    lowDensitySamples: lowDensitySamples,
  );

  if (keywordClassification != null) {
    if (keywordClassification.kind == kVideoKindScreenRecording) {
      return keywordClassification;
    }
    if (densityClassification != null &&
        densityClassification.confidence >=
            keywordClassification.confidence + 0.12) {
      return densityClassification;
    }
    return keywordClassification;
  }

  if (densityClassification != null) {
    return densityClassification;
  }

  if (totalChars <= 24) {
    return const VideoKindClassification(
      kind: kVideoKindVlog,
      confidence: 0.72,
    );
  }

  return const VideoKindClassification(kind: kVideoKindVlog, confidence: 0.62);
}

VideoKindClassification? _classifyFromFilename(String filename) {
  final normalized = filename.trim().toLowerCase();
  if (normalized.isEmpty) return null;

  final cameraRollPattern = RegExp(
    r'(^|[^a-z])(?:vid|mov|img|dji|gopr)_[0-9]{6,}',
    caseSensitive: false,
  );
  if (cameraRollPattern.hasMatch(normalized)) {
    return const VideoKindClassification(
        kind: kVideoKindVlog, confidence: 0.84);
  }

  final scoreByKind = _scoreKindsByKeywords(
    <String>[normalized.replaceAll(RegExp(r'[_\-.]+'), ' ')],
    _filenameKindRules,
  );
  final bestKind = _selectBestKindByScore(
    scoreByKind,
    _filenameKindRules,
    minScore: 1,
  );
  if (bestKind == null) return null;

  final rule = _lookupRuleByKind(_filenameKindRules, bestKind);
  if (rule == null) return null;
  final score = scoreByKind[bestKind] ?? 1;
  return VideoKindClassification(
    kind: bestKind,
    confidence: _confidenceFromKeywordScore(
      rule.baseConfidence,
      score,
      step: 0.03,
      max: 0.99,
    ),
  );
}

VideoKindClassification? _classifyFromOcrKeywords(
    List<String> recognizedTexts) {
  if (recognizedTexts.isEmpty) return null;

  final scoreByKind = _scoreKindsByKeywords(recognizedTexts, _ocrKindRules);
  _applyCompositeTextSignals(
    scoreByKind,
    recognizedTexts.join(' '),
  );

  final bestKind = _selectBestKindByScore(
    scoreByKind,
    _ocrKindRules,
    minScore: 2,
  );
  if (bestKind == null) return null;

  final rule = _lookupRuleByKind(_ocrKindRules, bestKind);
  if (rule == null) return null;

  final score = scoreByKind[bestKind] ?? 0;
  return VideoKindClassification(
    kind: bestKind,
    confidence: _confidenceFromKeywordScore(rule.baseConfidence, score),
  );
}

VideoKindClassification? _classifyScreenRecordingFromTextDensity({
  required int recognizedSamples,
  required int totalChars,
  required int maxChars,
  required int lowDensitySamples,
}) {
  if (recognizedSamples <= 0) return null;
  final averageChars = totalChars / recognizedSamples;

  if (maxChars >= 180 || averageChars >= 96 || totalChars >= 280) {
    return const VideoKindClassification(
      kind: kVideoKindScreenRecording,
      confidence: 0.86,
    );
  }

  if (maxChars >= 96 || totalChars >= 160) {
    return const VideoKindClassification(
      kind: kVideoKindScreenRecording,
      confidence: 0.74,
    );
  }

  if (recognizedSamples >= 3 && lowDensitySamples >= 3 && totalChars >= 96) {
    return const VideoKindClassification(
      kind: kVideoKindScreenRecording,
      confidence: 0.7,
    );
  }

  if (recognizedSamples >= 3 &&
      lowDensitySamples >= 3 &&
      totalChars >= 56 &&
      maxChars >= 18) {
    return const VideoKindClassification(
      kind: kVideoKindScreenRecording,
      confidence: 0.66,
    );
  }

  return null;
}

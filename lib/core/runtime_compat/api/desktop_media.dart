import '../desktop_media/ocr.dart';

Future<OcrPayload> desktopOcrImage(
        {required List<int> bytes, required String languageHints}) =>
    throw UnsupportedError('rust_runtime_removed:desktopOcrImage');

Future<OcrPayload> desktopOcrPdf(
        {required List<int> bytes,
        required int maxPages,
        required int dpi,
        required int startPage,
        required String languageHints}) =>
    throw UnsupportedError('rust_runtime_removed:desktopOcrPdf');

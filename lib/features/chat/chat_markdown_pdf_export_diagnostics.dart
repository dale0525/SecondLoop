import 'package:flutter/services.dart';

enum MarkdownPdfExportErrorKind {
  noWindowsBrowser,
  windowsBrowserPrintFailed,
  timeout,
  renderFailed,
  writeFailed,
  cancelled,
  notSupported,
  unknown,
}

MarkdownPdfExportErrorKind classifyMarkdownPdfExportError(Object error) {
  if (error is UnsupportedError) {
    return MarkdownPdfExportErrorKind.notSupported;
  }

  if (error is PlatformException) {
    final code = error.code.trim().toLowerCase();

    switch (code) {
      case 'markdown_pdf_export_timeout':
        return MarkdownPdfExportErrorKind.timeout;
      case 'markdown_pdf_export_layout_cancelled':
      case 'markdown_pdf_export_write_cancelled':
        return MarkdownPdfExportErrorKind.cancelled;
      case 'markdown_pdf_export_layout_failed':
      case 'markdown_pdf_export_webview_error':
      case 'markdown_pdf_export_navigation_failed':
      case 'markdown_pdf_export_js_probe_failed':
      case 'markdown_pdf_export_missing_webview':
        return MarkdownPdfExportErrorKind.renderFailed;
      case 'markdown_pdf_export_io_failed':
      case 'markdown_pdf_export_write_failed':
        return MarkdownPdfExportErrorKind.writeFailed;
      case 'markdown_pdf_export_unsupported_platform':
        return MarkdownPdfExportErrorKind.notSupported;
      default:
        break;
    }
  }

  final lowerMessage = error.toString().toLowerCase();
  if (lowerMessage.contains('no supported windows browser executable')) {
    return MarkdownPdfExportErrorKind.noWindowsBrowser;
  }
  if (lowerMessage.contains('windows markdown pdf export failed')) {
    return MarkdownPdfExportErrorKind.windowsBrowserPrintFailed;
  }
  if (lowerMessage.contains('timed out') || lowerMessage.contains('timeout')) {
    return MarkdownPdfExportErrorKind.timeout;
  }
  if (lowerMessage.contains('cancelled') || lowerMessage.contains('canceled')) {
    return MarkdownPdfExportErrorKind.cancelled;
  }

  return MarkdownPdfExportErrorKind.unknown;
}

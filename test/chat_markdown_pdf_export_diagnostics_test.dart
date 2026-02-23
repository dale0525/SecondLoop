import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/chat/chat_markdown_pdf_export_diagnostics.dart';

void main() {
  test('classifies missing Windows browser error from state message', () {
    final error = StateError(
      'No supported Windows browser executable found for markdown PDF export',
    );

    expect(
      classifyMarkdownPdfExportError(error),
      MarkdownPdfExportErrorKind.noWindowsBrowser,
    );
  });

  test('classifies Windows browser print failure from state message', () {
    final error =
        StateError('Windows markdown PDF export failed: [new] exit=1');

    expect(
      classifyMarkdownPdfExportError(error),
      MarkdownPdfExportErrorKind.windowsBrowserPrintFailed,
    );
  });

  test('classifies timeout from platform code', () {
    final error = PlatformException(
      code: 'markdown_pdf_export_timeout',
      message: 'timed out',
    );

    expect(
      classifyMarkdownPdfExportError(error),
      MarkdownPdfExportErrorKind.timeout,
    );
  });

  test('classifies render failure from layout and probe errors', () {
    final layoutError = PlatformException(
      code: 'markdown_pdf_export_layout_failed',
    );
    final probeError = PlatformException(
      code: 'markdown_pdf_export_js_probe_failed',
    );

    expect(
      classifyMarkdownPdfExportError(layoutError),
      MarkdownPdfExportErrorKind.renderFailed,
    );
    expect(
      classifyMarkdownPdfExportError(probeError),
      MarkdownPdfExportErrorKind.renderFailed,
    );
  });

  test('classifies write failure and cancellation from platform code', () {
    final writeError = PlatformException(
      code: 'markdown_pdf_export_write_failed',
    );
    final cancelledError = PlatformException(
      code: 'markdown_pdf_export_write_cancelled',
    );

    expect(
      classifyMarkdownPdfExportError(writeError),
      MarkdownPdfExportErrorKind.writeFailed,
    );
    expect(
      classifyMarkdownPdfExportError(cancelledError),
      MarkdownPdfExportErrorKind.cancelled,
    );
  });

  test('returns unknown for unrelated error', () {
    expect(
      classifyMarkdownPdfExportError(Exception('something else')),
      MarkdownPdfExportErrorKind.unknown,
    );
  });
}

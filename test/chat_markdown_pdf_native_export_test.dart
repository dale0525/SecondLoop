import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/chat/chat_markdown_pdf_native_export.dart';

void main() {
  test('Windows browser candidates prioritize Edge stable path', () {
    final candidates = buildWindowsBrowserCandidatePaths(
      const <String, String>{
        'PROGRAMFILES': r'C:\Program Files',
        'PROGRAMFILES(X86)': r'C:\Program Files (x86)',
        'LOCALAPPDATA': r'C:\Users\Alice\AppData\Local',
      },
    );

    expect(
      candidates.first,
      r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    );
    expect(candidates,
        contains(r'C:\Program Files\Google\Chrome\Application\chrome.exe'));
  });

  test('Windows headless print arguments include output and source url', () {
    final args = buildWindowsHeadlessPdfArguments(
      pdfOutputPath: r'C:\Temp\out.pdf',
      htmlSourceUri: Uri.parse('file:///C:/Temp/in.html'),
      headlessMode: 'new',
    );

    expect(args, contains('--headless=new'));
    expect(args, contains(r'--print-to-pdf=C:\Temp\out.pdf'));
    expect(args.last, 'file:///C:/Temp/in.html');
  });

  test(
      'Native export payload includes normalized page background color when set',
      () {
    final payload = buildNativeMarkdownPdfPayloadForTest(
      html: '<p>hello</p>',
      pageBackgroundColorHex: 'FFF8F3E8',
    );

    expect(payload['html'], '<p>hello</p>');
    expect(payload['pageBackgroundColorHex'], '#fff8f3e8');
  });

  test('Native export payload omits invalid page background color', () {
    final payload = buildNativeMarkdownPdfPayloadForTest(
      html: '<p>hello</p>',
      pageBackgroundColorHex: 'not-a-color',
    );

    expect(payload['html'], '<p>hello</p>');
    expect(payload.containsKey('pageBackgroundColorHex'), isFalse);
  });
}

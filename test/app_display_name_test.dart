import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Platform display names use "SecondLoop"', () {
    expect(_androidApplicationLabel(), 'SecondLoop');

    expect(_plistStringValue('ios/Runner/Info.plist', 'CFBundleDisplayName'),
        'SecondLoop');
    expect(_plistStringValue('ios/Runner/Info.plist', 'CFBundleName'),
        'SecondLoop');

    final webManifest = jsonDecode(File('web/manifest.json').readAsStringSync())
        as Map<String, Object?>;
    expect(webManifest['name'], 'SecondLoop');
    expect(webManifest['short_name'], 'SecondLoop');

    final webIndex = File('web/index.html').readAsStringSync();
    expect(_htmlMetaNameContent(webIndex, 'apple-mobile-web-app-title'),
        'SecondLoop');
    expect(_htmlTitle(webIndex), 'SecondLoop');

    final linuxShell = File('linux/my_application.cc').readAsStringSync();
    expect(_gtkStringArgValue(linuxShell, 'gtk_header_bar_set_title'),
        'SecondLoop');
    expect(
        _gtkStringArgValue(linuxShell, 'gtk_window_set_title'), 'SecondLoop');

    final windowsMain = File('windows/runner/main.cpp').readAsStringSync();
    expect(_windowsCreateTitle(windowsMain), 'SecondLoop');

    final windowsRc = File('windows/runner/Runner.rc').readAsStringSync();
    expect(_windowsRcValue(windowsRc, 'FileDescription'), 'SecondLoop');
    expect(_windowsRcValue(windowsRc, 'ProductName'), 'SecondLoop');

    expect(
        _xcconfigValue('macos/Runner/Configs/AppInfo.xcconfig', 'PRODUCT_NAME'),
        'SecondLoop');
  });
}

String _androidApplicationLabel() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final match = RegExp(r'android:label="([^"]+)"').firstMatch(manifest);
  if (match == null) {
    fail(
        'Could not find android:label in android/app/src/main/AndroidManifest.xml');
  }
  return match.group(1)!;
}

String _plistStringValue(String path, String key) {
  final content = File(path).readAsStringSync();
  final match =
      RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(content);
  if (match == null) {
    fail('Could not find <$key> string value in $path');
  }
  return match.group(1)!;
}

String _htmlMetaNameContent(String html, String name) {
  final match =
      RegExp('<meta\\s+name="$name"\\s+content="([^"]*)"', multiLine: true)
          .firstMatch(html);
  if (match == null) {
    fail('Could not find <meta name="$name" content="...">');
  }
  return match.group(1)!;
}

String _htmlTitle(String html) {
  final match =
      RegExp('<title>([^<]*)</title>', multiLine: true).firstMatch(html);
  if (match == null) {
    fail('Could not find <title> in web/index.html');
  }
  return match.group(1)!;
}

String _gtkStringArgValue(String code, String functionName) {
  final match =
      RegExp('$functionName\\([^,]+,\\s*"([^"]+)"\\)', multiLine: true)
          .firstMatch(code);
  if (match == null) {
    fail(
        'Could not find $functionName(..., "...") call in linux/my_application.cc');
  }
  return match.group(1)!;
}

String _windowsCreateTitle(String code) {
  final match =
      RegExp(r'window\.Create\(L"([^"]+)"', multiLine: true).firstMatch(code);
  if (match == null) {
    fail(
        'Could not find window.Create(L"...") call in windows/runner/main.cpp');
  }
  return match.group(1)!;
}

String _windowsRcValue(String content, String key) {
  final match =
      RegExp('VALUE "$key", "([^"]+)"', multiLine: true).firstMatch(content);
  if (match == null) {
    fail('Could not find VALUE "$key", "..." in windows/runner/Runner.rc');
  }
  return match.group(1)!;
}

String _xcconfigValue(String path, String key) {
  final content = File(path).readAsStringSync();
  final match = RegExp('^\\s*$key\\s*=\\s*(.+)\\s*\$', multiLine: true)
      .firstMatch(content);
  if (match == null) {
    fail('Could not find "$key = ..." in $path');
  }
  return match.group(1)!;
}

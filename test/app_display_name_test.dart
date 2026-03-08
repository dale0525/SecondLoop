import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _appleAppNamePlaceholder = r'$(SECONDLOOP_APP_NAME:default=SecondLoop)';

void main() {
  test(
      'Platform display names default to SecondLoop and support app-name overrides',
      () {
    expect(_androidApplicationLabelTemplate(), r'${appName}');
    expect(_androidDefaultApplicationName(), 'SecondLoop');
    expect(_androidDevApplicationName(), 'SecondLoop Dev');

    expect(
      _plistStringValue('ios/Runner/Info.plist', 'CFBundleDisplayName'),
      _appleAppNamePlaceholder,
    );
    expect(
      _plistStringValue('ios/Runner/Info.plist', 'CFBundleName'),
      _appleAppNamePlaceholder,
    );

    final webManifest = jsonDecode(File('web/manifest.json').readAsStringSync())
        as Map<String, Object?>;
    expect(webManifest['name'], 'SecondLoop');
    expect(webManifest['short_name'], 'SecondLoop');

    final webIndex = File('web/index.html').readAsStringSync();
    expect(_htmlMetaNameContent(webIndex, 'apple-mobile-web-app-title'),
        'SecondLoop');
    expect(_htmlTitle(webIndex), 'SecondLoop');

    final linuxShell = File('linux/my_application.cc').readAsStringSync();
    expect(_linuxAppNameMacro(linuxShell), 'SecondLoop');
    expect(
      linuxShell.contains(
          'gtk_header_bar_set_title(header_bar, SECONDLOOP_APP_NAME);'),
      isTrue,
    );
    expect(
      linuxShell.contains('gtk_window_set_title(window, SECONDLOOP_APP_NAME);'),
      isTrue,
    );

    final windowsMain = File('windows/runner/main.cpp').readAsStringSync();
    expect(_windowsWindowTitleMacro(windowsMain), 'SecondLoop');
    expect(
      windowsMain
          .contains('window.Create(SECONDLOOP_WINDOW_TITLE, origin, size)'),
      isTrue,
    );

    final windowsCmake =
        File('windows/runner/CMakeLists.txt').readAsStringSync();
    expect(
      windowsCmake.contains(
        r'if("${SECONDLOOP_APP_ID}" STREQUAL "com.secondloop.secondloopdev")',
      ),
      isTrue,
    );
    expect(
      windowsCmake.contains('set(SECONDLOOP_APP_NAME "SecondLoop Dev")'),
      isTrue,
    );
    expect(windowsCmake.contains('SECONDLOOP_FILE_DESCRIPTION'), isTrue);
    expect(windowsCmake.contains('SECONDLOOP_PRODUCT_NAME'), isTrue);

    final windowsRc = File('windows/runner/Runner.rc').readAsStringSync();
    expect(
      windowsRc.contains(
        'VALUE "CompanyName", SECONDLOOP_COMPANY_NAME "\\0"',
      ),
      isTrue,
    );
    expect(
      windowsRc.contains(
        'VALUE "FileDescription", SECONDLOOP_FILE_DESCRIPTION "\\0"',
      ),
      isTrue,
    );
    expect(
      windowsRc.contains(
        'VALUE "ProductName", SECONDLOOP_PRODUCT_NAME "\\0"',
      ),
      isTrue,
    );

    expect(
      _xcconfigValue('macos/Runner/Configs/AppInfo.xcconfig', 'PRODUCT_NAME'),
      _appleAppNamePlaceholder,
    );
  });
}

String _androidApplicationLabelTemplate() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final match = RegExp(r'android:label="([^"]+)"').firstMatch(manifest);
  if (match == null) {
    fail(
        'Could not find android:label in android/app/src/main/AndroidManifest.xml');
  }
  return match.group(1)!;
}

String _androidDefaultApplicationName() {
  final buildGradle = File('android/app/build.gradle').readAsStringSync();
  final match = RegExp(
    r'else\s*\{\s*secondloopApplicationName = "([^"]+)"',
    dotAll: true,
  ).firstMatch(buildGradle);
  if (match == null) {
    fail(
        'Could not find default SECONDLOOP_APP_NAME assignment in android/app/build.gradle');
  }
  return match.group(1)!;
}

String _androidDevApplicationName() {
  final buildGradle = File('android/app/build.gradle').readAsStringSync();
  final match = RegExp(
    r'if \(secondloopApplicationId == "com.secondloop.secondloopdev"\)\s*\{\s*secondloopApplicationName = "([^"]+)"',
    dotAll: true,
  ).firstMatch(buildGradle);
  if (match == null) {
    fail(
        'Could not find dev SECONDLOOP_APP_NAME assignment in android/app/build.gradle');
  }
  return match.group(1)!;
}

String _linuxAppNameMacro(String source) {
  final match =
      RegExp(r'#define SECONDLOOP_APP_NAME "([^"]+)"').firstMatch(source);
  if (match == null) {
    fail('Could not find SECONDLOOP_APP_NAME macro in linux/my_application.cc');
  }
  return match.group(1)!;
}

String _windowsWindowTitleMacro(String source) {
  final match =
      RegExp(r'#define SECONDLOOP_WINDOW_TITLE L"([^"]+)"').firstMatch(source);
  if (match == null) {
    fail(
        'Could not find SECONDLOOP_WINDOW_TITLE macro in windows/runner/main.cpp');
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

String _xcconfigValue(String path, String key) {
  final content = File(path).readAsStringSync();
  final pattern =
      r'^\s*__KEY__\s*=\s*(.+)\s*$'.replaceFirst('__KEY__', RegExp.escape(key));
  final match = RegExp(pattern, multiLine: true).firstMatch(content);
  if (match == null) {
    fail('Could not find "$key = ..." in $path');
  }
  return match.group(1)!;
}

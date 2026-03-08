import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/i18n/strings.g.dart';

void main() {
  test('generated translations remain accessible after refresh', () {
    expect(AppLocale.en.translations.settings.about.title, isNotEmpty);
    expect(AppLocale.zhCn.translations.settings.about.title, isNotEmpty);
    expect(AppLocale.en.translations.attachments.workspace.tabs.content,
        isNotEmpty);
    expect(AppLocale.zhCn.translations.attachments.workspace.tabs.content,
        isNotEmpty);
  });
}

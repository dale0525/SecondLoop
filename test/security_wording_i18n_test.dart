import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/i18n/strings.g.dart';

void main() {
  setUp(() {
    LocaleSettings.setLocale(AppLocale.en);
  });

  test('English sync wording uses recovery passphrase', () {
    LocaleSettings.setLocale(AppLocale.en);

    expect(
      t.sync.cloudManagedVault.setPassphraseDialog.title,
      'Set recovery passphrase (Advanced)',
    );
    expect(
      t.sync.missingSyncKey,
      'Enter your recovery passphrase and tap Save first.',
    );
    expect(t.sync.fields.passphrase.label, 'Recovery passphrase (Advanced)');
  });

  test('Chinese sync wording uses 恢复口令', () {
    LocaleSettings.setLocale(AppLocale.zhCn);

    expect(t.sync.cloudManagedVault.setPassphraseDialog.title, '设置恢复口令（高级）');
    expect(t.sync.missingSyncKey, '缺少恢复口令。请先输入口令并点击保存。');
    expect(t.sync.fields.passphrase.label, '恢复口令（高级）');
  });
}

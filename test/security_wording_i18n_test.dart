import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/i18n/strings.g.dart';

void main() {
  setUp(() {
    LocaleSettings.setLocale(AppLocale.en);
  });

  test('English security wording uses app lock password', () {
    LocaleSettings.setLocale(AppLocale.en);

    expect(t.common.fields.masterPassword, 'App lock password');
    expect(t.lock.masterPasswordRequired, 'App lock password required');
    expect(t.lock.setupTitle, 'Set app lock password');
    expect(
      t.lock.missingSavedSessionKey,
      'Missing saved session key. Unlock with app lock password once.',
    );
    expect(
      t.settings.systemUnlock.subtitleMobile,
      'Unlock with biometrics instead of app lock password',
    );
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

  test('Chinese wording uses 应用锁密码 and 恢复口令', () {
    LocaleSettings.setLocale(AppLocale.zhCn);

    expect(t.common.fields.masterPassword, '应用锁密码');
    expect(t.lock.masterPasswordRequired, '需要应用锁密码');
    expect(t.lock.setupTitle, '设置应用锁密码');
    expect(t.sync.cloudManagedVault.setPassphraseDialog.title, '设置恢复口令（高级）');
    expect(t.sync.missingSyncKey, '缺少恢复口令。请先输入口令并点击保存。');
    expect(t.sync.fields.passphrase.label, '恢复口令（高级）');
  });
}

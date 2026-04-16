import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/web_app/web_persistent_app_dir.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('web app dir resolver returns a stable vault-scoped path', () async {
    final resolver = OpfsWebPersistentAppDirResolver();

    final first = await resolver.resolve(uid: 'uid-1');
    final second = await resolver.resolve(uid: 'uid-1');

    expect(first, second);
    expect(first, '/opfs/secondloop/vaults/uid-1/v0');
  });

  test('web app dir resolver trims uid input', () async {
    final resolver = OpfsWebPersistentAppDirResolver();

    final appDir = await resolver.resolve(uid: '  uid-2  ');

    expect(appDir, '/opfs/secondloop/vaults/uid-2/v0');
  });

  test('web app dir resolver bumps generation when requested', () async {
    final resolver = OpfsWebPersistentAppDirResolver();

    final initialGeneration = await resolver.readGeneration(uid: 'uid-3');
    final bumpedGeneration = await resolver.bumpGeneration(uid: 'uid-3');
    final appDir = await resolver.resolve(uid: 'uid-3');

    expect(initialGeneration, 0);
    expect(bumpedGeneration, 1);
    expect(appDir, '/opfs/secondloop/vaults/uid-3/v1');
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/desktop/windows_velopack_uninstall_cleanup.dart';

void main() {
  test('cleanup plan targets Setup app data, cache, and product registry', () {
    final plan = buildWindowsVelopackUninstallCleanupPlan(
      environment: {
        'APPDATA': r'C:\Users\dev\AppData\Roaming',
        'LOCALAPPDATA': r'C:\Users\dev\AppData\Local',
      },
      appId: 'com.secondloop.secondloopdev',
      productName: 'SecondLoop Dev',
    );

    expect(
      plan.directories,
      containsAll([
        r'C:\Users\dev\AppData\Roaming\com.secondloop\SecondLoop Dev',
        r'C:\Users\dev\AppData\Local\com.secondloop\SecondLoop Dev',
      ]),
    );
    expect(
      plan.registryKeys,
      contains(r'HKCU\Software\SecondLoop\SecondLoop Dev'),
    );
    expect(
      plan.directories,
      isNot(
          contains(r'C:\Users\dev\AppData\Local\com.secondloop.secondloopdev')),
    );
  });

  test('cleanup removes directories and invokes registry cleanup best effort',
      () async {
    final tempRoot = Directory.systemTemp.createTempSync(
      'secondloop_velopack_uninstall_',
    );
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    final roaming = Directory('${tempRoot.path}/Roaming');
    final local = Directory('${tempRoot.path}/Local');
    final appData = Directory('${roaming.path}/com.secondloop/SecondLoop');
    final cacheData = Directory('${local.path}/com.secondloop/SecondLoop');
    appData.createSync(recursive: true);
    cacheData.createSync(recursive: true);
    File('${appData.path}/shared_preferences.json').writeAsStringSync('{}');
    File('${appData.path}/flutter_secure_storage.dat').writeAsBytesSync([1]);

    final registryCommands = <List<String>>[];

    await cleanWindowsVelopackUninstallResidue(
      isWindows: true,
      environment: {
        'APPDATA': roaming.path,
        'LOCALAPPDATA': local.path,
      },
      appId: 'com.secondloop.secondloop',
      productName: 'SecondLoop',
      registryCommandRunner: (executable, arguments) async {
        registryCommands.add([executable, ...arguments]);
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(appData.existsSync(), false);
    expect(cacheData.existsSync(), false);
    expect(Directory('${roaming.path}/com.secondloop').existsSync(), false);
    expect(Directory('${local.path}/com.secondloop').existsSync(), false);
    expect(
      registryCommands,
      contains(equals([
        'reg.exe',
        'delete',
        r'HKCU\Software\SecondLoop\SecondLoop',
        '/f',
      ])),
    );
  });

  test('cleanup keeps company directory when sibling app data remains',
      () async {
    final tempRoot = Directory.systemTemp.createTempSync(
      'secondloop_velopack_uninstall_sibling_',
    );
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    final roaming = Directory('${tempRoot.path}/Roaming');
    final local = Directory('${tempRoot.path}/Local');
    final appData = Directory('${roaming.path}/com.secondloop/SecondLoop');
    final siblingData =
        Directory('${roaming.path}/com.secondloop/SecondLoop Dev');
    final cacheData = Directory('${local.path}/com.secondloop/SecondLoop');
    appData.createSync(recursive: true);
    siblingData.createSync(recursive: true);
    cacheData.createSync(recursive: true);

    await cleanWindowsVelopackUninstallResidue(
      isWindows: true,
      environment: {
        'APPDATA': roaming.path,
        'LOCALAPPDATA': local.path,
      },
      registryCommandRunner: (_, __) async => ProcessResult(1, 0, '', ''),
    );

    expect(appData.existsSync(), false);
    expect(siblingData.existsSync(), true);
    expect(Directory('${roaming.path}/com.secondloop').existsSync(), true);
  });

  test('cleanup removes empty SecondLoop parent registry key', () async {
    final deletedKeys = <String>[];

    await cleanWindowsVelopackUninstallResidue(
      isWindows: true,
      environment: const {},
      registryCommandRunner: (executable, arguments) async {
        if (arguments.first == 'query') {
          return ProcessResult(1, 0, r'HKCU\Software\SecondLoop', '');
        }
        if (arguments.first == 'delete') {
          deletedKeys.add(arguments[1]);
        }
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(
      deletedKeys,
      containsAll([
        r'HKCU\Software\SecondLoop\SecondLoop',
        r'HKCU\Software\SecondLoop',
      ]),
    );
  });

  test('cleanup keeps SecondLoop parent registry key with sibling product',
      () async {
    final deletedKeys = <String>[];

    await cleanWindowsVelopackUninstallResidue(
      isWindows: true,
      environment: const {},
      registryCommandRunner: (executable, arguments) async {
        if (arguments.first == 'query') {
          return ProcessResult(
            1,
            0,
            'HKCU\\Software\\SecondLoop\n'
                'HKCU\\Software\\SecondLoop\\SecondLoop Dev\n',
            '',
          );
        }
        if (arguments.first == 'delete') {
          deletedKeys.add(arguments[1]);
        }
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(deletedKeys, contains(r'HKCU\Software\SecondLoop\SecondLoop'));
    expect(deletedKeys, isNot(contains(r'HKCU\Software\SecondLoop')));
  });

  test(
      'cleanup keeps parent registry key when query expands HKCU to full hive name',
      () async {
    final deletedKeys = <String>[];

    await cleanWindowsVelopackUninstallResidue(
      isWindows: true,
      environment: const {},
      registryCommandRunner: (executable, arguments) async {
        if (arguments.first == 'query') {
          return ProcessResult(
            1,
            0,
            'HKEY_CURRENT_USER\\Software\\SecondLoop\n'
                'HKEY_CURRENT_USER\\Software\\SecondLoop\\SecondLoop Dev\n',
            '',
          );
        }
        if (arguments.first == 'delete') {
          deletedKeys.add(arguments[1]);
        }
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(deletedKeys, contains(r'HKCU\Software\SecondLoop\SecondLoop'));
    expect(deletedKeys, isNot(contains(r'HKCU\Software\SecondLoop')));
  });

  test('cleanup does not remove environment root when company name is empty',
      () async {
    final tempRoot = Directory.systemTemp.createTempSync(
      'secondloop_velopack_uninstall_root_guard_',
    );
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final roaming = Directory('${tempRoot.path}/Roaming');
    final local = Directory('${tempRoot.path}/Local');
    final appData = Directory('${roaming.path}/SecondLoop');
    final cacheData = Directory('${local.path}/SecondLoop');
    appData.createSync(recursive: true);
    cacheData.createSync(recursive: true);

    await cleanWindowsVelopackUninstallResidue(
      isWindows: true,
      environment: {
        'APPDATA': roaming.path,
        'LOCALAPPDATA': local.path,
      },
      companyName: '',
      registryCommandRunner: (_, __) async => ProcessResult(1, 0, '', ''),
    );

    expect(appData.existsSync(), false);
    expect(cacheData.existsSync(), false);
    expect(roaming.existsSync(), true);
    expect(local.existsSync(), true);
  });

  test('cleanup is a no-op outside Windows', () async {
    var registryCalled = false;

    await cleanWindowsVelopackUninstallResidue(
      isWindows: false,
      registryCommandRunner: (_, __) async {
        registryCalled = true;
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(registryCalled, false);
  });
}

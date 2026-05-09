import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/runtime_test_profile_injector.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('injects self-managed runtime profile', () async {
    final store = RuntimeConnectionStore();
    final injector = RuntimeTestProfileInjector(connectionStore: store);

    await injector.injectSelfManaged(apiBaseUrl: 'https://runtime.example/');

    final connection = await store.loadConnection();
    expect(connection?.profile.runtimeMode, CloudRuntimeMode.selfManaged);
    expect(connection?.manifest.apiBaseUrl, 'https://runtime.example/');
  });

  test('injects managed pro runtime profile and can clear it', () async {
    final store = RuntimeConnectionStore();
    final injector = RuntimeTestProfileInjector(connectionStore: store);

    await injector.injectManagedPro(apiBaseUrl: 'https://managed.example/');
    expect(
      (await store.loadConnection())?.profile.runtimeMode,
      CloudRuntimeMode.managedPro,
    );

    await injector.clear();

    expect(await store.loadConnection(), isNull);
  });
}

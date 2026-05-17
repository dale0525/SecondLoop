import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/media_annotation/media_annotation_config_store.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  group('DartMediaAnnotationConfigStore', () {
    late DartMediaAnnotationConfigStore store;
    late Uint8List key;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = const DartMediaAnnotationConfigStore();
      key = Uint8List.fromList(List<int>.filled(32, 4));
    });

    test('persists media annotation config in Dart storage', () async {
      const config = MediaAnnotationConfig(
        annotateEnabled: false,
        searchEnabled: false,
        allowCellular: true,
        providerMode: 'byok',
        byokProfileId: 'profile-1',
        cloudModelName: 'vision-model',
      );

      await store.write(key, config);
      final restored = await store.read(key);

      expect(restored.annotateEnabled, isTrue);
      expect(restored.searchEnabled, isTrue);
      expect(restored.allowCellular, isTrue);
      expect(restored.providerMode, 'byok');
      expect(restored.byokProfileId, 'profile-1');
      expect(restored.cloudModelName, 'vision-model');
    });
  });
}

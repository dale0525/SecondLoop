import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine_gate.dart';

void main() {
  testWidgets('blob repair state is not attached to runtime-first sync gate',
      (tester) async {
    Object? engine;

    await tester.pumpWidget(
      MaterialApp(
        home: SyncEngineGate(
          child: Builder(
            builder: (context) {
              engine = SyncEngineScope.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(engine, isNull);
  });

  test('SyncEngineGate does not rehydrate managed-vault blob repair state', () {
    final source =
        File('lib/core/sync/sync_engine_gate.dart').readAsStringSync();

    expect(source, isNot(contains('writeManagedVaultMediaUploadPending')));
    expect(source, isNot(contains('readManagedVaultMediaUploadPending')));
    expect(source, isNot(contains('managedVaultBlobRepair')));
  });
}

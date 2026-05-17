import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine_gate.dart';

void main() {
  test('stale write-gate rehydrate result is ignored after scope switch', () {
    expect(
      shouldApplySyncEngineGateWriteGateRehydration(
        requestVersion: 1,
        latestVersion: 2,
        expectedBackendType: null,
        activeBackendType: null,
        expectedScopeId: 'scope-a',
        activeScopeId: 'scope-b',
      ),
      isFalse,
    );
  });

  test('matching write-gate rehydrate result is accepted', () {
    expect(
      shouldApplySyncEngineGateWriteGateRehydration(
        requestVersion: 2,
        latestVersion: 2,
        expectedBackendType: null,
        activeBackendType: null,
        expectedScopeId: 'runtime-profile',
        activeScopeId: 'runtime-profile',
      ),
      isTrue,
    );
  });

  testWidgets('scope switch no longer starts managed-vault media sync',
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
}

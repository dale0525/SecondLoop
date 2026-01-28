import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/features/settings/vault_usage_card.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Vault usage summary shows used/limit and breakdown',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: Scaffold(
            body: VaultUsageSummaryView(
              summary: VaultUsageSummary(
                totalBytesUsed: 1536,
                attachmentsBytesUsed: 1024,
                opsBytesUsed: 512,
                otherBytesUsed: 0,
                limitBytes: 10 * 1024,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Used:'), findsOneWidget);
    expect(find.text('Limit:'), findsOneWidget);
    expect(find.text('Photos & files:'), findsOneWidget);
    expect(find.text('Sync history:'), findsOneWidget);
  });
}

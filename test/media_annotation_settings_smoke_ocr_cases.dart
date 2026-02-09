part of 'media_annotation_settings_smoke_test.dart';

void _registerOcrModeTests() {
  testWidgets('Free users can switch OCR engine mode to BYOK multimodal',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(mediaUnderstandingEnabled: true),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      subscriptionStatus: SubscriptionStatus.notEntitled,
      backend: TestAppBackend(),
    );

    final scrollable = find.byType(Scrollable).first;
    final ocrModeTile = find.byKey(MediaAnnotationSettingsPage.ocrModeTileKey);
    await tester.scrollUntilVisible(
      ocrModeTile,
      220,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(ocrModeTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('BYOK multimodal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(contentStore.writes, isNotEmpty);
    expect(contentStore.writes.last.ocrEngineMode, 'multimodal_llm');
  });

  testWidgets('Pro users cannot override OCR engine mode from settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = _FakeMediaAnnotationConfigStore(
      _defaultMediaConfig(
        mediaUnderstandingEnabled: true,
        providerMode: 'cloud_gateway',
      ),
    );
    final contentStore = _FakeContentEnrichmentConfigStore(
      _defaultContentConfig(mediaUnderstandingEnabled: true),
    );

    await _pumpPage(
      tester,
      store: store,
      contentStore: contentStore,
      subscriptionStatus: SubscriptionStatus.entitled,
      backend: TestAppBackend(),
    );

    final scrollable = find.byType(Scrollable).first;
    final ocrModeTile = find.byKey(MediaAnnotationSettingsPage.ocrModeTileKey);
    await tester.scrollUntilVisible(
      ocrModeTile,
      220,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(ocrModeTile);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}

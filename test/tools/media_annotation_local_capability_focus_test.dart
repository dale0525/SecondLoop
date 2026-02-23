import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media local capability card keeps highlight focus wiring', () {
    final localCapabilityContent = File(
      'lib/features/settings/media_annotation_settings_page_local_capability.dart',
    ).readAsStringSync();
    final embeddedContent = File(
      'lib/features/settings/media_annotation_settings_page_embedded.dart',
    ).readAsStringSync();
    final sectionsContent = File(
      'lib/features/settings/media_annotation_settings_sections.dart',
    ).readAsStringSync();

    expect(localCapabilityContent, contains('_highlightLocalCapabilityCard'));
    expect(
      localCapabilityContent,
      contains('_mutateState(() => _highlightLocalCapabilityCard = true);'),
    );
    expect(
      embeddedContent,
      contains('highlighted: _highlightLocalCapabilityCard,'),
    );
    expect(sectionsContent, contains('bool highlighted = false,'));
    expect(sectionsContent, contains('AnimatedContainer('));
  });

  test('media local capability deep focus wires desktop fallback anchor', () {
    final pageContent = File(
      'lib/features/settings/media_annotation_settings_page.dart',
    ).readAsStringSync();
    final localCapabilityContent = File(
      'lib/features/settings/media_annotation_settings_page_local_capability.dart',
    ).readAsStringSync();
    final linuxOcrContent = File(
      'lib/features/settings/media_annotation_settings_page_linux_ocr.dart',
    ).readAsStringSync();

    expect(
      pageContent,
      contains('final GlobalKey _desktopLocalCapabilityCardAnchorKey'),
    );
    expect(
      localCapabilityContent,
      contains('BuildContext? _localCapabilityCardFocusContext()'),
    );
    expect(
      localCapabilityContent,
      contains('_desktopLocalCapabilityCardAnchorKey.currentContext'),
    );
    expect(
      localCapabilityContent,
      contains('bool _shouldShowDesktopLocalCapabilityCard()'),
    );
    expect(
      linuxOcrContent,
      contains('anchorKey: _desktopLocalCapabilityCardAnchorKey,'),
    );
  });
}

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
}

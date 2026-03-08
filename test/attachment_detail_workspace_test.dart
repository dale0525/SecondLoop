import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_detail_workspace.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('AttachmentDetailWorkspace renders desktop inspector layout',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentDetailWorkspace(
              title: 'Project call recording',
              typeLabel: 'Audio',
              metrics: const [
                AttachmentDetailMetric(label: 'Type', value: 'audio/mp4'),
                AttachmentDetailMetric(label: 'Duration', value: '00:42'),
              ],
              preview: Container(
                key: const ValueKey('workspace_preview_child'),
                height: 240,
                color: Colors.blue,
              ),
              content: const Text('Transcript body'),
              metadataItems: const [
                AttachmentDetailMetadataItem(
                  label: 'File size',
                  value: '128 KB',
                ),
                AttachmentDetailMetadataItem(
                  label: 'Source',
                  value: 'Recorder',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('attachment_detail_workspace')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_detail_header_bar')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_detail_preview_pane')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_detail_inspector')),
        findsOneWidget);
    expect(find.text('Project call recording'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Transcript body'), findsOneWidget);
    expect(find.text('File size'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('attachment_detail_tab_metadata')));
    await tester.pumpAndSettle();

    expect(find.text('File size'), findsOneWidget);
    expect(find.text('128 KB'), findsOneWidget);
    expect(find.text('Transcript body'), findsNothing);
  });

  testWidgets('AttachmentDetailWorkspace stacks on narrow screens',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentDetailWorkspace(
              title: 'Design spec',
              typeLabel: 'PDF',
              metrics: const [
                AttachmentDetailMetric(label: 'Pages', value: '12'),
              ],
              preview: Container(
                key: const ValueKey('workspace_preview_child_mobile'),
                height: 200,
                color: Colors.green,
              ),
              content: const Text('Extracted text'),
              metadataItems: const [
                AttachmentDetailMetadataItem(label: 'Pages', value: '12'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final previewTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey('attachment_detail_preview_pane')));
    final inspectorTopLeft = tester
        .getTopLeft(find.byKey(const ValueKey('attachment_detail_inspector')));
    expect(inspectorTopLeft.dy, greaterThan(previewTopLeft.dy));
  });
}

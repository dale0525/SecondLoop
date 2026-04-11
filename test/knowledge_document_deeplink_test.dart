import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/chat/knowledge_document_deeplink.dart';

void main() {
  test('parseKnowledgeDocumentDeepLink keeps unit targeting metadata', () {
    final parsed = parseKnowledgeDocumentDeepLink(
      'secondloop://knowledge-document/external%3Adoc-1?chunk=7&unit=external%3Adoc-1%3Achunk%3A0007',
    );

    expect(parsed, isNotNull);
    expect(parsed!.documentId, 'external:doc-1');
    expect(parsed.chunkIndex, 7);
    expect(parsed.unitId, 'external:doc-1:chunk:0007');
  });
}

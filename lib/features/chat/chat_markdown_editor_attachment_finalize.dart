import '../attachments/attachment_draft_send_contract.dart';
import 'chat_markdown_attachment_refs.dart';

typedef MarkdownEditorAttachmentIngestor = Future<String> Function(
  AttachmentDraftPayload draft,
);

final class FinalizedMarkdownEditorAttachments {
  const FinalizedMarkdownEditorAttachments({
    required this.markdown,
    required this.referencedAttachmentShas,
    required this.ingestedAttachmentShaByLocalId,
  });

  final String markdown;
  final Set<String> referencedAttachmentShas;
  final Map<String, String> ingestedAttachmentShaByLocalId;
}

Future<FinalizedMarkdownEditorAttachments> finalizeMarkdownEditorAttachments({
  required String markdown,
  required List<AttachmentDraftPayload> draftAttachments,
  required MarkdownEditorAttachmentIngestor ingestAttachment,
}) async {
  final referencedLocalIds = collectDraftMarkdownImageLocalIds(markdown);
  final attachmentShaByLocalId = <String, String>{};
  for (final draft in draftAttachments) {
    if (!referencedLocalIds.contains(draft.localId)) {
      continue;
    }
    attachmentShaByLocalId[draft.localId] = await ingestAttachment(draft);
  }

  final rewrittenMarkdown = rewriteDraftMarkdownImageRefs(
    markdown,
    attachmentShaByLocalId,
  );
  final unresolvedLocalIds =
      collectDraftMarkdownImageLocalIds(rewrittenMarkdown);
  if (unresolvedLocalIds.isNotEmpty) {
    throw StateError(
      'Unresolved markdown draft image refs: ${unresolvedLocalIds.join(', ')}',
    );
  }

  return FinalizedMarkdownEditorAttachments(
    markdown: rewrittenMarkdown,
    referencedAttachmentShas:
        collectPersistedMarkdownAttachmentShas(rewrittenMarkdown),
    ingestedAttachmentShaByLocalId: Map<String, String>.unmodifiable(
      attachmentShaByLocalId,
    ),
  );
}

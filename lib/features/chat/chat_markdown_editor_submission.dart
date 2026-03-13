import '../../src/rust/db.dart';
import '../attachments/attachment_draft_send_contract.dart';
import 'chat_markdown_editor_attachment_finalize.dart';

typedef MarkdownEditorCreateMessage = Future<Message> Function(String content);
typedef MarkdownEditorEditMessage = Future<void> Function(
  String messageId,
  String content,
);
typedef MarkdownEditorLinkAttachmentToMessage = Future<void> Function(
  String messageId,
  String attachmentSha256,
);

final class MarkdownEditorSubmissionResult {
  const MarkdownEditorSubmissionResult({
    required this.messageId,
    required this.markdown,
    required this.referencedAttachmentShas,
    required this.ingestedAttachmentShaByLocalId,
  });

  final String messageId;
  final String markdown;
  final Set<String> referencedAttachmentShas;
  final Map<String, String> ingestedAttachmentShaByLocalId;
}

Future<MarkdownEditorSubmissionResult> sendMarkdownEditorMessage({
  required String markdown,
  required List<AttachmentDraftPayload> draftAttachments,
  required MarkdownEditorAttachmentIngestor ingestAttachment,
  required MarkdownEditorCreateMessage createMessage,
  required MarkdownEditorLinkAttachmentToMessage linkAttachmentToMessage,
}) async {
  final finalized = await finalizeMarkdownEditorAttachments(
    markdown: markdown,
    draftAttachments: draftAttachments,
    ingestAttachment: ingestAttachment,
  );

  final message = await createMessage(finalized.markdown);
  for (final attachmentSha in finalized.referencedAttachmentShas) {
    await linkAttachmentToMessage(message.id, attachmentSha);
  }

  return MarkdownEditorSubmissionResult(
    messageId: message.id,
    markdown: finalized.markdown,
    referencedAttachmentShas: finalized.referencedAttachmentShas,
    ingestedAttachmentShaByLocalId: finalized.ingestedAttachmentShaByLocalId,
  );
}

Future<MarkdownEditorSubmissionResult> editMarkdownEditorMessage({
  required String messageId,
  required String markdown,
  required List<AttachmentDraftPayload> draftAttachments,
  required MarkdownEditorAttachmentIngestor ingestAttachment,
  required MarkdownEditorEditMessage editMessage,
  required MarkdownEditorLinkAttachmentToMessage linkAttachmentToMessage,
}) async {
  final finalized = await finalizeMarkdownEditorAttachments(
    markdown: markdown,
    draftAttachments: draftAttachments,
    ingestAttachment: ingestAttachment,
  );

  await editMessage(messageId, finalized.markdown);
  for (final attachmentSha in finalized.referencedAttachmentShas) {
    await linkAttachmentToMessage(messageId, attachmentSha);
  }

  return MarkdownEditorSubmissionResult(
    messageId: messageId,
    markdown: finalized.markdown,
    referencedAttachmentShas: finalized.referencedAttachmentShas,
    ingestedAttachmentShaByLocalId: finalized.ingestedAttachmentShaByLocalId,
  );
}

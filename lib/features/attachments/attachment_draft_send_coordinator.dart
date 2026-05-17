import 'package:secondloop/core/models/app_models.dart';
import 'attachment_draft_send_contract.dart';

typedef CreateUserMessage = Future<Message> Function(String content);
typedef IngestAttachmentDraft = Future<String> Function(
    AttachmentDraftPayload draft);
typedef LinkAttachmentToMessage = Future<void> Function(
  String messageId,
  String attachmentSha256,
);
typedef AttachmentLinkedCallback = Future<void> Function(
  String attachmentSha256,
  AttachmentDraftPayload draft,
);
typedef AttachmentDraftProgressCallback = void Function(
  AttachmentDraftProgress progress,
);

final class AttachmentDraftSendCoordinator {
  const AttachmentDraftSendCoordinator();

  Future<SendDraftResult> send({
    required String text,
    required List<AttachmentDraftPayload> drafts,
    required CreateUserMessage createUserMessage,
    required IngestAttachmentDraft ingestAttachment,
    required LinkAttachmentToMessage linkAttachmentToMessage,
    AttachmentLinkedCallback? onAttachmentLinked,
    AttachmentDraftProgressCallback? onProgress,
    String attachmentOnlyFallbackText = '',
  }) async {
    final normalizedText = text.trim();
    final dedupedDrafts = dedupeAttachmentDraftPayloads(drafts);

    if (normalizedText.isEmpty && dedupedDrafts.isEmpty) {
      return SendDraftResult(
        messageId: null,
        sourceMessageId: null,
        linkedAttachmentShas: const <String>[],
        failedItems: const <FailedAttachmentDraft>[],
        attemptedCount: 0,
      );
    }

    final failedItems = <FailedAttachmentDraft>[];
    final ingested = <(AttachmentDraftPayload payload, String sha256)>[];
    var message = null as Message?;

    if (normalizedText.isNotEmpty) {
      try {
        message = await createUserMessage(normalizedText);
      } catch (error) {
        for (final draft in dedupedDrafts) {
          failedItems.add(
            FailedAttachmentDraft(
              payload: draft,
              kind: SendFailureKind.messageCreateFailed,
              error: '$error',
            ),
          );
          onProgress?.call(
            AttachmentDraftProgress(
              localId: draft.localId,
              status: AttachmentDraftItemStatus.failed,
              failureKind: SendFailureKind.messageCreateFailed,
              error: '$error',
            ),
          );
        }

        return SendDraftResult(
          messageId: null,
          sourceMessageId: null,
          linkedAttachmentShas: const <String>[],
          failedItems: failedItems,
          attemptedCount: dedupedDrafts.length,
        );
      }
    }

    for (final draft in dedupedDrafts) {
      onProgress?.call(
        AttachmentDraftProgress(
          localId: draft.localId,
          status: AttachmentDraftItemStatus.ingesting,
        ),
      );

      try {
        final sha256 = await ingestAttachment(draft);
        ingested.add((draft, sha256));
      } catch (error) {
        failedItems.add(
          FailedAttachmentDraft(
            payload: draft,
            kind: SendFailureKind.ingestFailed,
            error: '$error',
          ),
        );
        onProgress?.call(
          AttachmentDraftProgress(
            localId: draft.localId,
            status: AttachmentDraftItemStatus.failed,
            failureKind: SendFailureKind.ingestFailed,
            error: '$error',
          ),
        );
      }
    }

    if (message == null && ingested.isNotEmpty) {
      final fallbackText = attachmentOnlyFallbackText.trim();
      try {
        message = await createUserMessage(fallbackText);
      } catch (error) {
        for (final (payload, _) in ingested) {
          failedItems.add(
            FailedAttachmentDraft(
              payload: payload,
              kind: SendFailureKind.messageCreateFailed,
              error: '$error',
            ),
          );
          onProgress?.call(
            AttachmentDraftProgress(
              localId: payload.localId,
              status: AttachmentDraftItemStatus.failed,
              failureKind: SendFailureKind.messageCreateFailed,
              error: '$error',
            ),
          );
        }

        return SendDraftResult(
          messageId: null,
          sourceMessageId: null,
          linkedAttachmentShas: const <String>[],
          failedItems: failedItems,
          attemptedCount: dedupedDrafts.length,
        );
      }
    }

    if (message == null) {
      return SendDraftResult(
        messageId: null,
        sourceMessageId: null,
        linkedAttachmentShas: const <String>[],
        failedItems: failedItems,
        attemptedCount: dedupedDrafts.length,
      );
    }

    final linkedAttachmentShas = <String>[];
    for (final (payload, sha256) in ingested) {
      try {
        await linkAttachmentToMessage(message.id, sha256);
        linkedAttachmentShas.add(sha256);
        if (onAttachmentLinked != null) {
          await onAttachmentLinked(sha256, payload);
        }
        onProgress?.call(
          AttachmentDraftProgress(
            localId: payload.localId,
            status: AttachmentDraftItemStatus.linked,
            attachmentSha256: sha256,
          ),
        );
      } catch (error) {
        failedItems.add(
          FailedAttachmentDraft(
            payload: payload,
            kind: SendFailureKind.linkFailed,
            error: '$error',
          ),
        );
        onProgress?.call(
          AttachmentDraftProgress(
            localId: payload.localId,
            status: AttachmentDraftItemStatus.failed,
            failureKind: SendFailureKind.linkFailed,
            error: '$error',
          ),
        );
      }
    }

    return SendDraftResult(
      messageId: message.id,
      sourceMessageId: message.id,
      linkedAttachmentShas: linkedAttachmentShas,
      failedItems: failedItems,
      attemptedCount: dedupedDrafts.length,
    );
  }
}

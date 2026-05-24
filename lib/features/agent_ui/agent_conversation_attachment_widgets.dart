part of 'agent_conversation_page.dart';

final class _MessageAttachmentStrip extends StatelessWidget {
  const _MessageAttachmentStrip({required this.attachments});

  final List<_AgentMessageAttachmentView> attachments;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('agent_message_attachment_strip'),
      spacing: AgentDesignTokens.gapSm,
      runSpacing: AgentDesignTokens.gapSm,
      children: [
        for (final attachment in attachments)
          _MessageAttachmentTile(attachment: attachment),
      ],
    );
  }
}

final class _MessageAttachmentTile extends StatelessWidget {
  const _MessageAttachmentTile({required this.attachment});

  final _AgentMessageAttachmentView attachment;

  @override
  Widget build(BuildContext context) {
    final previewBytes = attachment.bytes;
    return SizedBox(
      width: 180,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('agent_message_attachment_chip_${attachment.id}'),
          borderRadius: BorderRadius.circular(AgentDesignTokens.radiusSm),
          onTap: () => _openAttachment(context),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.72),
              borderRadius: BorderRadius.circular(AgentDesignTokens.radiusSm),
              border: Border.all(color: const Color(0xFFBFD2FF)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AgentDesignTokens.gapSm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height:
                        attachment.isImage && previewBytes != null ? 72 : 48,
                    child: attachment.isImage && previewBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AgentDesignTokens.radiusSm,
                            ),
                            child: Image.memory(
                              previewBytes,
                              key: ValueKey(
                                'agent_message_attachment_image_${attachment.id}',
                              ),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.image_outlined, size: 22),
                              ),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.attach_file_rounded, size: 24),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    attachment.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _AgentConversationPageState._ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  if (attachment.sizeLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      attachment.sizeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _AgentConversationPageState._muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openAttachment(BuildContext context) {
    final attachmentId = attachment.id.trim();
    if (attachmentId.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          AttachmentViewerPage(
            attachment: Attachment(
              sha256: attachmentId,
              mimeType: attachment.mimeType,
              path: attachment.filename,
              byteLen: attachment.bytes?.length ?? 0,
              createdAtMs: 0,
            ),
            initialBytes: attachment.bytes,
          ),
        ),
      ),
    );
  }
}

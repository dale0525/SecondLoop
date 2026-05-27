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
    final colors = context.agentOs;
    final previewBytes = attachment.bytes;
    final isImage = attachment.isImage && previewBytes != null;
    final isAudio = attachment.isAudio && !isImage;
    return SizedBox(
      width: isImage ? 240 : (isAudio ? 250 : 180),
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
              child: isAudio
                  ? _AudioMessageAttachmentTileBody(attachment: attachment)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: isImage ? 112 : 48,
                          child: isImage
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
                                      child:
                                          Icon(Icons.image_outlined, size: 22),
                                    ),
                                  ),
                                )
                              : const Center(
                                  child:
                                      Icon(Icons.attach_file_rounded, size: 24),
                                ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          attachment.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurface,
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
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
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

final class _AudioMessageAttachmentTileBody extends StatelessWidget {
  const _AudioMessageAttachmentTileBody({required this.attachment});

  final _AgentMessageAttachmentView attachment;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    final secondary = attachment.secondaryLabel;
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.secondaryContainer.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AgentDesignTokens.radiusSm),
          ),
          child: SizedBox.square(
            key: ValueKey('agent_message_attachment_audio_${attachment.id}'),
            dimension: 42,
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: colors.secondary,
              size: 26,
            ),
          ),
        ),
        const SizedBox(width: AgentDesignTokens.gapSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                attachment.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              if (secondary.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

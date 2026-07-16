use crate::mail::{MailDraft, MailError, MailResult};
use crate::mail_attachments::ResolvedDraftAttachment;
use lettre::{
    Message,
    message::{
        Attachment as LettreAttachment, MessageBuilder, MultiPart, SinglePart, header::ContentType,
    },
};

pub(super) fn build_outgoing_message(
    builder: MessageBuilder,
    draft: &MailDraft,
    attachments: Vec<ResolvedDraftAttachment>,
) -> MailResult<Message> {
    let message = if attachments.is_empty() {
        match &draft.content.body.html {
            Some(html) => builder.multipart(MultiPart::alternative_plain_html(
                draft.content.body.plain_text.clone(),
                html.clone(),
            )),
            None => builder.body(draft.content.body.plain_text.clone()),
        }
    } else {
        let mut mixed = match &draft.content.body.html {
            Some(html) => MultiPart::mixed().multipart(MultiPart::alternative_plain_html(
                draft.content.body.plain_text.clone(),
                html.clone(),
            )),
            None => MultiPart::mixed()
                .singlepart(SinglePart::plain(draft.content.body.plain_text.clone())),
        };
        for attachment in attachments {
            let content_type =
                ContentType::parse(&attachment.metadata.mime_type).map_err(|_| {
                    MailError::InvalidRequest("outgoing attachment MIME type is invalid".into())
                })?;
            mixed = mixed.singlepart(
                LettreAttachment::new(attachment.metadata.file_name)
                    .body(attachment.data, content_type),
            );
        }
        builder.multipart(mixed)
    }
    .map_err(|_| MailError::InvalidRequest("outgoing message could not be encoded".into()))?;
    Ok(message)
}

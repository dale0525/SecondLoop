use super::*;
use crate::attachments::SqliteAttachmentStore;
use crate::storage::Storage;

fn scope(user: &str) -> AttachmentScope {
    AttachmentScope::new("app", "tenant", user).unwrap()
}

#[tokio::test]
async fn stored_source_resolves_only_exact_scoped_immutable_metadata() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = SqliteAttachmentStore::from_storage(&storage).await.unwrap();
    let metadata = store
        .import(
            &scope("user"),
            "brief.txt",
            "text/plain",
            b"authoritative attachment",
            "mail-attachment-1",
        )
        .await
        .unwrap();
    let source = StoredMailAttachmentSource::new(store.clone(), scope("user"));
    let attachment = DraftAttachment {
        host_attachment_id: Some(metadata.id.clone()),
        source_message_id: None,
        source_attachment_id: None,
        file_name: metadata.file_name.clone(),
        mime_type: metadata.mime_type.clone(),
        size_bytes: metadata.size_bytes,
        sha256: Some(metadata.sha256.clone()),
    };
    let resolved = source.resolve("primary", &attachment).await.unwrap();
    assert_eq!(resolved.data, b"authoritative attachment");

    let mut drifted = attachment.clone();
    drifted.file_name = "changed.txt".into();
    assert!(source.resolve("primary", &drifted).await.is_err());
    let other_scope = StoredMailAttachmentSource::new(store.clone(), scope("other"));
    assert!(other_scope.resolve("primary", &attachment).await.is_err());
    store.delete(&scope("user"), &metadata.id).await.unwrap();
    assert!(source.resolve("primary", &attachment).await.is_err());
}

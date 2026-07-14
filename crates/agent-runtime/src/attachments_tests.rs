use super::*;

fn scope(user: &str) -> AttachmentScope {
    AttachmentScope::new("com.example.app", "local", user).unwrap()
}

#[tokio::test]
async fn attachments_are_scoped_idempotent_bounded_and_deletable() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = SqliteAttachmentStore::from_storage(&storage).await.unwrap();
    let first = store
        .import(
            &scope("user"),
            "brief.txt",
            "text/plain",
            b"authoritative attachment",
            "import-1",
        )
        .await
        .unwrap();
    let repeated = store
        .import(
            &scope("user"),
            "brief.txt",
            "text/plain",
            b"authoritative attachment",
            "import-1",
        )
        .await
        .unwrap();
    assert_eq!(first.id, repeated.id);
    assert!(store.list(&scope("other"), 10).await.unwrap().is_empty());
    assert_eq!(
        store
            .import(
                &scope("user"),
                "different.txt",
                "text/plain",
                b"different",
                "import-1",
            )
            .await
            .unwrap_err(),
        AttachmentError::IdempotencyConflict,
    );

    let chunk = store.read(&scope("user"), &first.id, 0, 4).await.unwrap();
    assert_eq!(STANDARD.decode(chunk.data_base64).unwrap(), b"auth");
    assert!(chunk.truncated);
    assert!(store.delete(&scope("user"), &first.id).await.unwrap());
    assert!(
        store
            .get(&scope("user"), &first.id)
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn attachment_import_rejects_paths_and_oversized_content() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = SqliteAttachmentStore::from_storage(&storage).await.unwrap();
    assert!(
        store
            .import(&scope("user"), "../secret", "text/plain", b"x", "key")
            .await
            .is_err()
    );
    assert_eq!(
        store
            .import(
                &scope("user"),
                "large.bin",
                "application/octet-stream",
                &vec![0; MAX_ATTACHMENT_BYTES + 1],
                "large",
            )
            .await
            .unwrap_err(),
        AttachmentError::TooLarge,
    );
}

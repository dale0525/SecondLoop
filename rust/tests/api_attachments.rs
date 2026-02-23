use secondloop_rust::api::core;

#[test]
fn api_can_link_list_and_read_attachments() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let app_dir = tmp.path().to_string_lossy().to_string();

    let key = vec![7u8; 32];
    let conversation =
        core::db_get_or_create_main_stream_conversation(app_dir.clone(), key.clone())
            .expect("get main stream conversation");
    let message = core::db_insert_message(
        app_dir.clone(),
        key.clone(),
        conversation.id,
        "user".to_string(),
        "hello".to_string(),
    )
    .expect("insert message");

    let bytes = vec![1u8, 2, 3, 4, 5];
    let meta = core::db_insert_attachment(
        app_dir.clone(),
        key.clone(),
        bytes.clone(),
        "image/png".to_string(),
    )
    .expect("insert attachment");

    let message_id = message.id.clone();
    core::db_link_attachment_to_message(
        app_dir.clone(),
        key.clone(),
        message_id.clone(),
        meta.sha256.clone(),
    )
    .expect("link attachment");
    let listed = core::db_list_message_attachments(app_dir.clone(), key.clone(), message_id)
        .expect("list message attachments");
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].sha256, meta.sha256);

    let roundtrip =
        core::db_read_attachment_bytes(app_dir.clone(), key.clone(), meta.sha256.clone())
            .expect("read attachment");
    assert_eq!(roundtrip, bytes);
}

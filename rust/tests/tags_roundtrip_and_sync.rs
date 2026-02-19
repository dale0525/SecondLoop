use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn tags_roundtrip_and_sync_between_devices() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTagsTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let conversation =
        db::create_conversation(&conn_a, &key_a, "Main").expect("create conversation");
    let message = db::insert_message(&conn_a, &key_a, &conversation.id, "user", "hello")
        .expect("insert message");

    let all_tags = db::list_tags(&conn_a, &key_a).expect("list tags");
    assert_eq!(all_tags.iter().filter(|t| t.is_system).count(), 10);

    let work_tag = db::upsert_tag(&conn_a, &key_a, "工作周报").expect("upsert work tag");
    assert!(work_tag.is_system);
    assert_eq!(work_tag.system_key.as_deref(), Some("work"));

    let custom_tag = db::upsert_tag(&conn_a, &key_a, "Project Alpha").expect("upsert custom tag");
    assert!(!custom_tag.is_system);
    assert_eq!(custom_tag.system_key, None);

    let applied = db::set_message_tags(
        &conn_a,
        &key_a,
        &message.id,
        &[work_tag.id.clone(), custom_tag.id.clone()],
    )
    .expect("set message tags");
    assert_eq!(applied.len(), 2);

    let matched_ids =
        db::list_message_ids_by_tag_ids(&conn_a, &conversation.id, &[work_tag.id.clone()])
            .expect("list ids by tag");
    assert_eq!(matched_ids, vec![message.id.clone()]);

    let attachment = db::insert_attachment(&conn_a, &key_a, &app_dir_a, b"abc", "image/png")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn_a, &key_a, &message.id, &attachment.sha256)
        .expect("link attachment");
    db::mark_attachment_annotation_ok(
        &conn_a,
        &key_a,
        &attachment.sha256,
        "zh-CN",
        "test-model",
        &serde_json::json!({"tags": ["工作", "运动", "Road Trip"]}),
        1_700_000_000_000,
    )
    .expect("annotation ok");

    let suggested =
        db::list_message_suggested_tags(&conn_a, &key_a, &message.id).expect("suggested tags");
    assert_eq!(suggested, vec!["work", "health", "travel"]);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync-tags",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let pulled = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(pulled > 0);

    let message_tags_b = db::list_message_tags(&conn_b, &key_b, &message.id).expect("tags on B");
    let ids_b = message_tags_b
        .iter()
        .map(|tag| tag.id.as_str())
        .collect::<std::collections::BTreeSet<_>>();
    assert!(ids_b.contains(work_tag.id.as_str()));
    assert!(ids_b.contains(custom_tag.id.as_str()));

    let all_tags_b = db::list_tags(&conn_b, &key_b).expect("all tags on B");
    assert!(all_tags_b.iter().any(|t| t.id == custom_tag.id));
}

#[test]
fn merged_custom_tag_is_deleted_and_synced() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTagMergeSyncTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let conversation =
        db::create_conversation(&conn_a, &key_a, "Main").expect("create conversation");
    let message = db::insert_message(&conn_a, &key_a, &conversation.id, "user", "weekly retro")
        .expect("insert message");

    let canonical = db::upsert_tag(&conn_a, &key_a, "Weekly Review").expect("upsert canonical");
    let alias = db::upsert_tag(&conn_a, &key_a, "weekly-review").expect("upsert alias");

    db::set_message_tags(&conn_a, &key_a, &message.id, &[alias.id.clone()]).expect("set alias tag");

    let updated = db::merge_tags(&conn_a, &key_a, &alias.id, &canonical.id).expect("merge tags");
    assert_eq!(updated, 1);

    let tags_a = db::list_tags(&conn_a, &key_a).expect("list tags on A");
    assert!(tags_a.iter().any(|tag| tag.id == canonical.id));
    assert!(!tags_a.iter().any(|tag| tag.id == alias.id));

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync-tag-merge",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let pulled = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(pulled > 0);

    let tags_b = db::list_tags(&conn_b, &key_b).expect("list tags on B");
    assert!(tags_b.iter().any(|tag| tag.id == canonical.id));
    assert!(!tags_b.iter().any(|tag| tag.id == alias.id));

    let message_tags_b =
        db::list_message_tags(&conn_b, &key_b, &message.id).expect("list tags on B");
    let ids_b = message_tags_b
        .iter()
        .map(|tag| tag.id.as_str())
        .collect::<std::collections::BTreeSet<_>>();
    assert!(ids_b.contains(canonical.id.as_str()));
    assert!(!ids_b.contains(alias.id.as_str()));
}

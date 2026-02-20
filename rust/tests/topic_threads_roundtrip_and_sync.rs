use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn topic_threads_roundtrip_and_sync_between_devices() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTopicThreadsTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let conversation =
        db::create_conversation(&conn_a, &key_a, "Main").expect("create conversation");
    let m1 = db::insert_message(&conn_a, &key_a, &conversation.id, "user", "alpha")
        .expect("insert message alpha");
    let _m2 = db::insert_message(&conn_a, &key_a, &conversation.id, "user", "beta")
        .expect("insert message beta");
    let m3 = db::insert_message(&conn_a, &key_a, &conversation.id, "assistant", "gamma")
        .expect("insert message gamma");

    let thread =
        db::create_topic_thread(&conn_a, &key_a, &conversation.id, Some("Weekly Highlights"))
            .expect("create topic thread");
    assert_eq!(thread.conversation_id, conversation.id);
    assert_eq!(thread.title.as_deref(), Some("Weekly Highlights"));

    let set_ids = db::set_topic_thread_message_ids(
        &conn_a,
        &key_a,
        &thread.id,
        &[m1.id.clone(), m3.id.clone(), m3.id.clone()],
    )
    .expect("set thread message ids");
    assert_eq!(set_ids, vec![m1.id.clone(), m3.id.clone()]);

    let listed_threads =
        db::list_topic_threads(&conn_a, &key_a, &conversation.id).expect("list threads");
    assert_eq!(listed_threads.len(), 1);
    assert_eq!(listed_threads[0].id, thread.id);

    let listed_ids =
        db::list_topic_thread_message_ids(&conn_a, &thread.id).expect("list thread ids");
    assert_eq!(listed_ids, vec![m1.id.clone(), m3.id.clone()]);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync-topic-threads",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let pulled = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(pulled > 0);

    let listed_threads_b =
        db::list_topic_threads(&conn_b, &key_b, &conversation.id).expect("list threads on B");
    assert_eq!(listed_threads_b.len(), 1);
    assert_eq!(listed_threads_b[0].id, thread.id);
    assert_eq!(
        listed_threads_b[0].title.as_deref(),
        Some("Weekly Highlights")
    );

    let listed_ids_b = db::list_topic_thread_message_ids(&conn_b, &thread.id)
        .expect("list thread message ids on B");
    assert_eq!(listed_ids_b, vec![m1.id, m3.id]);
}

#[test]
fn topic_thread_rename_and_delete_sync_between_devices() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTopicThreadsRenameDeleteTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let conversation =
        db::create_conversation(&conn_a, &key_a, "Main").expect("create conversation");
    let message = db::insert_message(&conn_a, &key_a, &conversation.id, "user", "alpha")
        .expect("insert message");

    let thread = db::create_topic_thread(&conn_a, &key_a, &conversation.id, Some("Initial"))
        .expect("create thread");
    db::set_topic_thread_message_ids(
        &conn_a,
        &key_a,
        &thread.id,
        std::slice::from_ref(&message.id),
    )
    .expect("set ids");

    let renamed = db::update_topic_thread_title(&conn_a, &key_a, &thread.id, Some("Renamed title"))
        .expect("rename thread");
    assert_eq!(renamed.title.as_deref(), Some("Renamed title"));

    let deleted = db::delete_topic_thread(&conn_a, &key_a, &thread.id).expect("delete thread");
    assert!(deleted);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync-topic-threads-rename-delete",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(pulled > 0);

    let threads_b =
        db::list_topic_threads(&conn_b, &key_b, &conversation.id).expect("list threads on B");
    assert!(threads_b.is_empty());

    let ids_b = db::list_topic_thread_message_ids(&conn_b, &thread.id)
        .expect("list thread message ids on B");
    assert!(ids_b.is_empty());
}

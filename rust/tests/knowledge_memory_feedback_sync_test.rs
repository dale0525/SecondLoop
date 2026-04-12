use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::knowledge::KnowledgeMemoryStatus;
use secondloop_rust::sync;

#[test]
fn knowledge_memory_feedback_syncs_between_devices() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopKnowledgeFeedbackSync";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let conv = db::create_conversation(&conn_a, &key_a, "Inbox").expect("conversation A");
    db::insert_message(
        &conn_a,
        &key_a,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("preference");
    secondloop_rust::knowledge::ensure_knowledge_rebuild_requested(&conn_a).expect("rebuild A");
    secondloop_rust::knowledge::process_pending_knowledge_index_jobs_active(&conn_a, &key_a, 256)
        .expect("process A");

    db::upsert_knowledge_memory_feedback(
        &conn_a,
        &key_a,
        "generated:preference:response-language",
        Some(KnowledgeMemoryStatus::Confirmed),
        false,
        false,
        true,
        Some("Preferred reply language".to_string()),
        Some("Always reply in Chinese unless I ask for another language.".to_string()),
    )
    .expect("feedback A");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");

    secondloop_rust::knowledge::ensure_knowledge_rebuild_requested(&conn_b).expect("rebuild B");
    secondloop_rust::knowledge::process_pending_knowledge_index_jobs_active(&conn_b, &key_b, 256)
        .expect("process B");

    let synced = secondloop_rust::knowledge::get_knowledge_document(
        &conn_b,
        &key_b,
        "generated:preference:response-language",
    )
    .expect("get doc B")
    .expect("doc B exists");

    assert_eq!(
        synced.memory_feedback.status,
        Some(KnowledgeMemoryStatus::Confirmed)
    );
    assert!(!synced.memory_feedback.use_for_ask_ai);
    assert!(synced.memory_feedback.marked_inaccurate);
    assert_eq!(synced.title.as_deref(), Some("Preferred reply language"));
    assert_eq!(
        synced.summary.as_deref(),
        Some("Always reply in Chinese unless I ask for another language.")
    );
}

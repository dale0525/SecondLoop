use std::path::Path;

use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

#[test]
fn reset_vault_data_preserves_llm_profiles_and_embedding_model() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(Path::new(&app_dir), "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conv = db::get_or_create_loop_home_conversation(&conn, &key).expect("loop home");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert message");

    db::create_llm_profile(
        &conn,
        &key,
        "OpenAI",
        "openai-compatible",
        Some("https://api.openai.com/v1"),
        Some("sk-test"),
        "gpt-4o-mini",
        true,
    )
    .expect("create llm profile");

    db::set_active_embedding_model_name(&conn, "secondloop-default-embed-v0")
        .expect("set embedding model");

    assert_eq!(
        db::list_messages(&conn, &key, &conv.id)
            .expect("list messages")
            .len(),
        1
    );
    assert_eq!(
        db::list_llm_profiles(&conn)
            .expect("list llm profiles")
            .len(),
        1
    );
    assert_eq!(
        db::get_active_embedding_model_name(&conn)
            .expect("get embedding model")
            .as_deref(),
        Some("secondloop-default-embed-v0")
    );

    db::reset_vault_data_preserving_llm_profiles(&conn).expect("reset vault data");

    assert_eq!(
        db::list_messages(&conn, &key, &conv.id)
            .expect("list messages after reset")
            .len(),
        0
    );
    assert_eq!(
        db::list_llm_profiles(&conn)
            .expect("list llm profiles after reset")
            .len(),
        1
    );
    assert_eq!(
        db::get_active_embedding_model_name(&conn)
            .expect("get embedding model after reset")
            .as_deref(),
        Some("secondloop-default-embed-v0")
    );
}

#[test]
fn clear_remote_root_deletes_localdir_data() {
    let remote_dir = tempfile::tempdir().expect("remote dir");
    let remote = sync::localdir::LocalDirRemoteStore::new(remote_dir.path().to_path_buf())
        .expect("create localdir remote");
    let remote_root = "SecondLoopTest";

    remote.mkdir_all(remote_root).expect("mkdir remote root");
    remote
        .put(
            &format!("{remote_root}/deviceA/ops/op_1.json"),
            br#"{"op_id":"1"}"#.to_vec(),
        )
        .expect("write remote op");

    let remote_root_path = remote_dir.path().join(remote_root);
    assert!(remote_root_path.exists(), "remote root should exist");

    sync::clear_remote_root(&remote, remote_root).expect("clear remote root");

    assert!(
        !remote_root_path.exists(),
        "remote root directory should be deleted"
    );
}

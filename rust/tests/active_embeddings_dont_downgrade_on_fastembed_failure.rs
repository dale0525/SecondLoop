use std::fs;

use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding::{DEFAULT_MODEL_NAME, PRODUCTION_MODEL_NAME};
use secondloop_rust::{auth, db};

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[test]
fn active_embeddings_dont_downgrade_on_fastembed_init_failure() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    db::set_active_embedding_model_name(&conn, PRODUCTION_MODEL_NAME).expect("set model");

    let dylib_name = if cfg!(target_os = "windows") {
        "onnxruntime.dll"
    } else if cfg!(target_os = "macos") {
        "libonnxruntime.dylib"
    } else if cfg!(target_os = "linux") {
        "libonnxruntime.so"
    } else {
        unreachable!("test only runs on desktop platforms");
    };

    let runtime_dir = app_dir.join("onnxruntime");
    fs::create_dir_all(&runtime_dir).expect("create runtime dir");
    fs::write(runtime_dir.join(dylib_name), b"not a real dylib").expect("write fake dylib");

    let result = db::process_pending_message_embeddings_active(&conn, &key, &app_dir, 32);
    assert!(
        result.is_err(),
        "expected fastembed init to fail; got {result:?}"
    );

    let stored = db::get_active_embedding_model_name(&conn).expect("get model");
    assert_eq!(stored.as_deref(), Some(PRODUCTION_MODEL_NAME));

    let processed_default: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM message_embeddings WHERE model_name = ?1",
            [DEFAULT_MODEL_NAME],
            |row| row.get(0),
        )
        .expect("count default embeddings");
    assert_eq!(
        processed_default, 0,
        "should not silently fall back to default embeddings"
    );
}


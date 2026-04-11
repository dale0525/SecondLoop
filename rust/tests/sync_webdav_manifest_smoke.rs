use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;
use serde_json::Value;

#[test]
fn webdav_push_writes_root_and_device_manifests() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop_a");
    let db_key = auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let sync_key = [7u8; 32];
    let remote = sync::InMemoryRemoteStore::new();

    let conv = db::create_conversation(&conn, &db_key, "Inbox").expect("create conversation");
    db::insert_message(&conn, &db_key, &conv.id, "user", "hello").expect("insert message");

    let pushed = sync::push(&conn, &db_key, &sync_key, &remote, "SecondLoop").expect("push");
    assert!(pushed > 0);

    let manifest_bytes = remote
        .get("/SecondLoop/sync_manifest.json")
        .expect("root manifest exists");
    let manifest_json: Value =
        serde_json::from_slice(&manifest_bytes).expect("parse root manifest");
    assert_eq!(manifest_json["backend"].as_str(), Some("webdav"));
    assert_eq!(manifest_json["protocol_version"].as_u64(), Some(1));
    assert!(manifest_json["generation_id"].as_str().is_some());

    let device_id: String = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device id");
    let device_manifest_path = format!("/SecondLoop/{device_id}/device_manifest.json");
    let device_manifest_bytes = remote
        .get(&device_manifest_path)
        .expect("device manifest exists");
    let device_manifest_json: Value =
        serde_json::from_slice(&device_manifest_bytes).expect("parse device manifest");
    assert_eq!(
        device_manifest_json["device_id"].as_str(),
        Some(device_id.as_str())
    );
    assert_eq!(device_manifest_json["protocol_version"].as_u64(), Some(1));
    assert!(device_manifest_json["max_seq"].as_i64().unwrap_or(0) >= 1);
}

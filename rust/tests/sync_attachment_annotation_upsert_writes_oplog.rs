use std::fs;

use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_mark_attachment_annotation_ok_writes_oplog_even_after_backfill_flag() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    fs::create_dir_all(&app_dir_a).expect("mkdir app dir");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let attachment =
        db::insert_attachment(&conn_a, &key_a, &app_dir_a, b"img", "image/jpeg").expect("attach");

    // Simulate that the user already ran a sync before this annotation existed.
    conn_a
        .execute(
            r#"INSERT INTO kv(key, value) VALUES ('oplog.backfill.attachment_annotations.v1', '1')
               ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
            [],
        )
        .expect("set annotations backfill flag");

    let now = 1_700_000_000_000i64;
    let ann_payload = serde_json::json!({
        "caption_long": "keyword_after_backfill",
        "tags": [],
        "ocr_text": null
    });
    db::mark_attachment_annotation_ok(
        &conn_a,
        &key_a,
        &attachment.sha256,
        "en",
        "test-model",
        &ann_payload,
        now,
    )
    .expect("mark annotation ok");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    fs::create_dir_all(&app_dir_b).expect("mkdir app dir B");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0);

    let caption = db::read_attachment_annotation_caption_long(&conn_b, &key_b, &attachment.sha256)
        .expect("read caption")
        .expect("caption present");
    assert_eq!(caption, "keyword_after_backfill");
}

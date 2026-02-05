use std::fs;

use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, encrypt_bytes, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_push_backfills_attachment_annotation_ops_for_legacy_rows() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let bytes = b"legacy attachment bytes with annotation";

    // Device A has legacy attachment + annotation rows (no oplog entries).
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    // Simulate old behavior: write attachment file + insert rows directly without oplog.
    let sha256 = {
        use sha2::{Digest, Sha256};
        let digest = Sha256::digest(bytes);
        let mut out = String::with_capacity(64);
        for b in digest {
            use std::fmt::Write;
            let _ = write!(&mut out, "{:02x}", b);
        }
        out
    };
    let rel_path = format!("attachments/{sha256}.bin");
    let full_path = app_dir_a.join(&rel_path);
    fs::create_dir_all(app_dir_a.join("attachments")).expect("mkdir attachments");
    let aad = format!("attachment.bytes:{sha256}");
    let blob = encrypt_bytes(&key_a, bytes, aad.as_bytes()).expect("encrypt attachment");
    fs::write(&full_path, blob).expect("write attachment");

    let now = 1_700_000_000_000i64;
    conn_a
        .execute(
            r#"INSERT INTO attachments(sha256, mime_type, path, byte_len, created_at)
               VALUES (?1, ?2, ?3, ?4, ?5)"#,
            rusqlite::params![sha256, "image/webp", rel_path, bytes.len() as i64, now],
        )
        .expect("insert attachment row");

    let ann_payload = serde_json::json!({
        "caption_long": "keyword_passport",
        "tags": ["passport"],
        "ocr_text": null
    });
    let ann_json = serde_json::to_vec(&ann_payload).expect("serialize annotation payload");
    let ann_aad = format!("attachment.annotation:{sha256}:en");
    let ann_blob =
        encrypt_bytes(&key_a, &ann_json, ann_aad.as_bytes()).expect("encrypt annotation payload");
    conn_a
        .execute(
            r#"
INSERT INTO attachment_annotations(
  attachment_sha256,
  status,
  lang,
  model_name,
  payload,
  attempts,
  next_retry_at,
  last_error,
  created_at,
  updated_at
)
VALUES (?1, 'ok', 'en', 'legacy-model', ?2, 0, NULL, NULL, ?3, ?3)
"#,
            rusqlite::params![sha256, ann_blob, now],
        )
        .expect("insert attachment annotation");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    // Device B pulls and sees annotation caption.
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0);

    let caption = db::read_attachment_annotation_caption_long(&conn_b, &key_b, &sha256)
        .expect("read annotation caption")
        .expect("caption present");
    assert_eq!(caption, "keyword_passport");
}

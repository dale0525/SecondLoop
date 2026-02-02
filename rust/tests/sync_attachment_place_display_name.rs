use std::fs;

use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, encrypt_bytes, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_push_backfills_attachment_place_ops_for_legacy_rows() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let bytes = b"legacy attachment bytes with geo";

    // Device A has legacy attachment + place rows (no oplog entries).
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

    let place_payload = serde_json::json!({
        "ok": true,
        "lang": "en",
        "display_name": "Pudong, Shanghai",
    });
    let place_json = serde_json::to_vec(&place_payload).expect("serialize place payload");
    let place_aad = format!("attachment.place:{sha256}:en");
    let place_blob =
        encrypt_bytes(&key_a, &place_json, place_aad.as_bytes()).expect("encrypt place payload");
    conn_a
        .execute(
            r#"
INSERT INTO attachment_places(
  attachment_sha256,
  status,
  lang,
  payload,
  attempts,
  next_retry_at,
  last_error,
  created_at,
  updated_at
)
VALUES (?1, 'ok', 'en', ?2, 0, NULL, NULL, ?3, ?3)
"#,
            rusqlite::params![sha256, place_blob, now],
        )
        .expect("insert attachment place");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    // Device B pulls and sees place display name.
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0);

    let place = db::read_attachment_place_display_name(&conn_b, &key_b, &sha256)
        .expect("read place")
        .expect("place present");
    assert_eq!(place, "Pudong, Shanghai");
}

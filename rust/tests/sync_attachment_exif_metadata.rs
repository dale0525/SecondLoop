use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_attachment_exif_metadata_is_replicated_via_oplog() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let bytes = b"pretend image bytes";

    // Device A creates attachment + EXIF metadata.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    // Simulate backfill already done so this test proves the upsert writes an oplog op.
    conn_a
        .execute(
            r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
               ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
            rusqlite::params!["oplog.backfill.attachment_exif.v1", "1"],
        )
        .expect("set exif backfill key");

    let attachment = db::insert_attachment(&conn_a, &key_a, &app_dir_a, bytes, "image/webp")
        .expect("insert attachment");
    db::upsert_attachment_exif_metadata(
        &conn_a,
        &key_a,
        &attachment.sha256,
        Some(1_700_000_123_000),
        Some(37.76667),
        Some(-122.41667),
    )
    .expect("upsert exif");

    // Device B is a fresh install.
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0);

    let meta = db::read_attachment_exif_metadata(&conn_b, &key_b, &attachment.sha256)
        .expect("read exif")
        .expect("exif present");

    assert_eq!(meta.captured_at_ms, Some(1_700_000_123_000));
    assert!((meta.latitude.unwrap() - 37.76667).abs() < 1e-6);
    assert!((meta.longitude.unwrap() - -122.41667).abs() < 1e-6);
}

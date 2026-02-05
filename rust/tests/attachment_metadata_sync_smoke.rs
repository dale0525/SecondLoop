use std::thread;
use std::time::Duration;

use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn attachment_metadata_sync_smoke() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    // Device A creates attachment + metadata oplog op.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let attachment = db::insert_attachment(&conn_a, &key_a, &app_dir_a, b"doc", "application/pdf")
        .expect("insert attachment");

    db::upsert_attachment_metadata(
        &conn_a,
        &key_a,
        &attachment.sha256,
        Some("Title A"),
        &["a.pdf".to_string()],
        &["https://example.com".to_string()],
    )
    .expect("upsert metadata A");

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

    let meta_b = db::read_attachment_metadata(&conn_b, &key_b, &attachment.sha256)
        .expect("read metadata B")
        .expect("metadata exists on B");
    assert_eq!(meta_b.title.as_deref(), Some("Title A"));
    assert_eq!(meta_b.filenames, vec!["a.pdf".to_string()]);
    assert_eq!(meta_b.source_urls, vec!["https://example.com".to_string()]);

    // Device B updates title + adds a filename. This should sync back to A as LWW/union.
    thread::sleep(Duration::from_millis(2));
    db::upsert_attachment_metadata(
        &conn_b,
        &key_b,
        &attachment.sha256,
        Some("Title B"),
        &["b.pdf".to_string()],
        &[],
    )
    .expect("upsert metadata B");

    let pushed_b = sync::push(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("push B");
    assert!(pushed_b > 0);

    let applied_a = sync::pull(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("pull A");
    assert!(applied_a > 0);

    let meta_a2 = db::read_attachment_metadata(&conn_a, &key_a, &attachment.sha256)
        .expect("read metadata A")
        .expect("metadata exists on A");
    let mut filenames_a2 = meta_a2.filenames;
    filenames_a2.sort();
    assert_eq!(meta_a2.title.as_deref(), Some("Title B"));
    assert_eq!(filenames_a2, vec!["a.pdf".to_string(), "b.pdf".to_string()]);
    assert_eq!(meta_a2.source_urls, vec!["https://example.com".to_string()]);
}

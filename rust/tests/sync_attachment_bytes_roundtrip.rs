use secondloop_rust::auth;
use secondloop_rust::crypto::{decrypt_bytes, derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

#[test]
fn sync_uploads_and_downloads_attachment_bytes_on_demand() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let bytes = b"image bytes for roundtrip";

    // Device A creates message + attachment + link.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let message =
        db::insert_message(&conn_a, &key_a, &conversation.id, "user", "hello").expect("message A");
    let attachment = db::insert_attachment(&conn_a, &key_a, &app_dir_a, bytes, "image/jpeg")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn_a, &key_a, &message.id, &attachment.sha256)
        .expect("link attachment");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    // Remote should contain encrypted attachment bytes.
    let remote_path = format!("/{remote_root}/attachments/{}.bin", attachment.sha256);
    let cipher = remote.get(&remote_path).expect("remote get attachment");
    let aad = format!("sync.attachment.bytes:{}", attachment.sha256);
    let plain = decrypt_bytes(&sync_key, &cipher, aad.as_bytes()).expect("decrypt remote bytes");
    assert_eq!(plain, bytes);

    // Device B pulls metadata/links, then downloads bytes on demand.
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0);

    assert!(
        db::read_attachment_bytes(&conn_b, &key_b, &app_dir_b, &attachment.sha256).is_err(),
        "bytes should be missing on B before download"
    );

    sync::download_attachment_bytes(
        &conn_b,
        &key_b,
        &sync_key,
        &remote,
        remote_root,
        &attachment.sha256,
    )
    .expect("download bytes");

    let roundtrip = db::read_attachment_bytes(&conn_b, &key_b, &app_dir_b, &attachment.sha256)
        .expect("read bytes after download");
    assert_eq!(roundtrip, bytes);
}

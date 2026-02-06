use std::fs;

use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn link_audio_attachment_auto_enqueues_transcribe_when_enabled() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let mut cfg = db::get_content_enrichment_config(&conn).expect("read config");
    cfg.url_fetch_enabled = false;
    cfg.document_extract_enabled = false;
    cfg.audio_transcribe_enabled = true;
    db::set_content_enrichment_config(&conn, &cfg).expect("write config");

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg = db::insert_message(&conn, &key, &conv.id, "user", "audio").expect("insert message");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"wav-bytes", "audio/wav")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn, &key, &msg.id, &attachment.sha256)
        .expect("link attachment");

    let due =
        db::list_due_attachment_annotations(&conn, i64::MAX, 10).expect("list due annotations");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].attachment_sha256, attachment.sha256);
}

#[test]
fn link_audio_attachment_does_not_auto_enqueue_when_disabled() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let mut cfg = db::get_content_enrichment_config(&conn).expect("read config");
    cfg.url_fetch_enabled = false;
    cfg.document_extract_enabled = false;
    cfg.audio_transcribe_enabled = false;
    db::set_content_enrichment_config(&conn, &cfg).expect("write config");

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg = db::insert_message(&conn, &key, &conv.id, "user", "audio").expect("insert message");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"wav-bytes", "audio/wav")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn, &key, &msg.id, &attachment.sha256)
        .expect("link attachment");

    let due =
        db::list_due_attachment_annotations(&conn, i64::MAX, 10).expect("list due annotations");
    assert!(due.is_empty());
}

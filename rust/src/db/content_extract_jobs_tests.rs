use super::*;

#[test]
fn is_supported_document_mime_type_includes_text_and_office_types() {
    assert!(is_supported_document_mime_type("application/pdf"));
    assert!(is_supported_document_mime_type(
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ));
    assert!(is_supported_document_mime_type("text/plain"));
    assert!(is_supported_document_mime_type("application/json"));
}

#[test]
fn is_supported_document_mime_type_excludes_binary_media_types() {
    assert!(!is_supported_document_mime_type("image/png"));
    assert!(!is_supported_document_mime_type("video/mp4"));
    assert!(!is_supported_document_mime_type("audio/mpeg"));
}

#[test]
fn url_manifest_mime_helper_matches_expected_type() {
    assert!(is_url_manifest_mime_type(
        "application/x.secondloop.url+json"
    ));
    assert!(!is_url_manifest_mime_type("application/json"));
}

#[test]
fn video_manifest_auto_enqueue_when_video_extract_enabled() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [3u8; 32];

    let mut cfg = get_content_enrichment_config(&conn).expect("config");
    cfg.url_fetch_enabled = false;
    cfg.document_extract_enabled = false;
    cfg.audio_transcribe_enabled = false;
    cfg.video_extract_enabled = true;
    set_content_enrichment_config(&conn, &cfg).expect("write config");

    let conv = create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg = insert_message(&conn, &key, &conv.id, "user", "video").expect("message");

    let manifest_payload = serde_json::json!({
        "schema": "secondloop.video_manifest.v2",
        "video_sha256": "sha-video",
        "video_mime_type": "video/mp4"
    });
    let manifest = insert_attachment(
        &conn,
        &key,
        &app_dir,
        manifest_payload.to_string().as_bytes(),
        "application/x.secondloop.video+json",
    )
    .expect("manifest");

    link_attachment_to_message(&conn, &key, &msg.id, &manifest.sha256).expect("link");

    let due = list_due_attachment_annotations(&conn, i64::MAX, 10).expect("due");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].attachment_sha256, manifest.sha256);
}

#[test]
fn process_pending_document_extractions_enriches_video_manifest_from_audio_transcript() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [4u8; 32];

    let mut cfg = get_content_enrichment_config(&conn).expect("config");
    cfg.document_extract_enabled = false;
    cfg.video_extract_enabled = true;
    cfg.audio_transcribe_enabled = false;
    cfg.url_fetch_enabled = false;
    set_content_enrichment_config(&conn, &cfg).expect("write config");

    let audio = insert_attachment(&conn, &key, &app_dir, b"m4a", "audio/mp4").expect("audio");
    mark_attachment_annotation_ok(
        &conn,
        &key,
        &audio.sha256,
        "und",
        "audio_transcript.v1",
        &serde_json::json!({
            "schema": "secondloop.audio_transcript.v1",
            "transcript_full": "audio transcript full",
            "transcript_excerpt": "audio transcript excerpt"
        }),
        1000,
    )
    .expect("mark transcript ok");

    let video_segment =
        insert_attachment(&conn, &key, &app_dir, b"mp4", "video/mp4").expect("video segment");
    let manifest_payload = serde_json::json!({
        "schema": "secondloop.video_manifest.v2",
        "video_sha256": video_segment.sha256,
        "video_mime_type": "video/mp4",
        "audio_sha256": audio.sha256,
        "audio_mime_type": "audio/mp4",
        "video_segments": [{
            "index": 0,
            "sha256": video_segment.sha256,
            "mime_type": "video/mp4"
        }]
    });

    let manifest = insert_attachment(
        &conn,
        &key,
        &app_dir,
        manifest_payload.to_string().as_bytes(),
        "application/x.secondloop.video+json",
    )
    .expect("manifest");
    enqueue_attachment_annotation(&conn, &manifest.sha256, "und", 1200).expect("enqueue manifest");

    let processed =
        process_pending_document_extractions(&conn, &key, &app_dir, 10).expect("process pending");
    assert_eq!(processed, 1);

    let payload_json = read_attachment_annotation_payload_json(&conn, &key, &manifest.sha256)
        .expect("read payload")
        .expect("payload exists");
    let payload: serde_json::Value =
        serde_json::from_str(&payload_json).expect("valid payload json");

    assert_eq!(
        payload["schema"].as_str(),
        Some("secondloop.video_extract.v1")
    );
    assert_eq!(
        payload["audio_sha256"].as_str(),
        Some(audio.sha256.as_str())
    );
    assert_eq!(
        payload["transcript_full"].as_str(),
        Some("audio transcript full")
    );
    assert_eq!(
        payload["readable_text_excerpt"].as_str(),
        Some("audio transcript excerpt")
    );
    assert_eq!(payload["needs_ocr"].as_bool(), Some(false));
}

#[test]
fn process_pending_video_manifest_enqueues_audio_transcript_when_missing_and_enabled() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [5u8; 32];

    let mut cfg = get_content_enrichment_config(&conn).expect("config");
    cfg.document_extract_enabled = false;
    cfg.video_extract_enabled = true;
    cfg.audio_transcribe_enabled = true;
    cfg.url_fetch_enabled = false;
    set_content_enrichment_config(&conn, &cfg).expect("write config");

    let audio = insert_attachment(&conn, &key, &app_dir, b"m4a", "audio/mp4").expect("audio");
    let video_segment =
        insert_attachment(&conn, &key, &app_dir, b"mp4", "video/mp4").expect("video segment");
    let manifest_payload = serde_json::json!({
        "schema": "secondloop.video_manifest.v2",
        "video_sha256": video_segment.sha256,
        "video_mime_type": "video/mp4",
        "audio_sha256": audio.sha256,
        "audio_mime_type": "audio/mp4",
        "video_segments": [{
            "index": 0,
            "sha256": video_segment.sha256,
            "mime_type": "video/mp4"
        }]
    });

    let manifest = insert_attachment(
        &conn,
        &key,
        &app_dir,
        manifest_payload.to_string().as_bytes(),
        "application/x.secondloop.video+json",
    )
    .expect("manifest");
    enqueue_attachment_annotation(&conn, &manifest.sha256, "und", 1200).expect("enqueue manifest");

    let processed =
        process_pending_document_extractions(&conn, &key, &app_dir, 10).expect("process pending");
    assert_eq!(processed, 0);

    let due_now = list_due_attachment_annotations(&conn, now_ms(), 10).expect("due now");
    assert!(
        due_now
            .iter()
            .any(|job| job.attachment_sha256 == audio.sha256),
        "missing due audio transcript job"
    );

    let manifest_status: String = conn
        .query_row(
            r#"SELECT status FROM attachment_annotations WHERE attachment_sha256 = ?1"#,
            rusqlite::params![manifest.sha256],
            |row| row.get(0),
        )
        .expect("manifest status");
    assert_eq!(manifest_status, "failed");

    let manifest_attempts: i64 = conn
        .query_row(
            r#"SELECT attempts FROM attachment_annotations WHERE attachment_sha256 = ?1"#,
            rusqlite::params![manifest.sha256],
            |row| row.get(0),
        )
        .expect("manifest attempts");
    assert_eq!(manifest_attempts, 1);

    let audio_status: String = conn
        .query_row(
            r#"SELECT status FROM attachment_annotations WHERE attachment_sha256 = ?1"#,
            rusqlite::params![audio.sha256],
            |row| row.get(0),
        )
        .expect("audio status");
    assert_eq!(audio_status, "pending");
}

#[test]
fn process_pending_video_manifest_skips_audio_wait_when_audio_transcribe_disabled() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [6u8; 32];

    let mut cfg = get_content_enrichment_config(&conn).expect("config");
    cfg.document_extract_enabled = false;
    cfg.video_extract_enabled = true;
    cfg.audio_transcribe_enabled = false;
    cfg.url_fetch_enabled = false;
    set_content_enrichment_config(&conn, &cfg).expect("write config");

    let audio = insert_attachment(&conn, &key, &app_dir, b"m4a", "audio/mp4").expect("audio");
    let video_segment =
        insert_attachment(&conn, &key, &app_dir, b"mp4", "video/mp4").expect("video segment");
    let manifest_payload = serde_json::json!({
        "schema": "secondloop.video_manifest.v2",
        "video_sha256": video_segment.sha256,
        "video_mime_type": "video/mp4",
        "audio_sha256": audio.sha256,
        "audio_mime_type": "audio/mp4",
        "video_segments": [{
            "index": 0,
            "sha256": video_segment.sha256,
            "mime_type": "video/mp4"
        }]
    });

    let manifest = insert_attachment(
        &conn,
        &key,
        &app_dir,
        manifest_payload.to_string().as_bytes(),
        "application/x.secondloop.video+json",
    )
    .expect("manifest");
    enqueue_attachment_annotation(&conn, &manifest.sha256, "und", 1200).expect("enqueue manifest");

    let processed =
        process_pending_document_extractions(&conn, &key, &app_dir, 10).expect("process pending");
    assert_eq!(processed, 1);

    let payload_json = read_attachment_annotation_payload_json(&conn, &key, &manifest.sha256)
        .expect("read payload")
        .expect("payload exists");
    let payload: serde_json::Value =
        serde_json::from_str(&payload_json).expect("valid payload json");

    assert_eq!(
        payload["schema"].as_str(),
        Some("secondloop.video_extract.v1")
    );
    assert_eq!(
        payload["audio_sha256"].as_str(),
        Some(audio.sha256.as_str())
    );
    assert_eq!(payload["transcript_full"], serde_json::Value::Null);
    assert_eq!(payload["needs_ocr"].as_bool(), Some(true));

    let audio_job_count: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM attachment_annotations WHERE attachment_sha256 = ?1"#,
            rusqlite::params![audio.sha256],
            |row| row.get(0),
        )
        .expect("audio job count");
    assert_eq!(audio_job_count, 0);
}

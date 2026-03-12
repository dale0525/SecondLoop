use secondloop_rust::db;

#[test]
fn video_attachment_derivations_backfill_from_legacy_manifest() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");
    let key = [5u8; 32];

    let segment =
        db::insert_attachment(&conn, &key, &app_dir, b"segment", "video/mp4").expect("segment");
    let poster =
        db::insert_attachment(&conn, &key, &app_dir, b"poster", "image/jpeg").expect("poster");
    let audio = db::insert_attachment(&conn, &key, &app_dir, b"audio", "audio/mp4").expect("audio");
    let keyframe =
        db::insert_attachment(&conn, &key, &app_dir, b"frame", "image/jpeg").expect("keyframe");

    let manifest_json = format!(
        r#"{{
          "schema":"secondloop.video_manifest.v3",
          "video_sha256":"{segment_sha}",
          "video_mime_type":"video/mp4",
          "video_proxy_sha256":"{segment_sha}",
          "video_segments":[{{"index":0,"sha256":"{segment_sha}","mime_type":"video/mp4"}}],
          "audio_sha256":"{audio_sha}",
          "audio_mime_type":"audio/mp4",
          "poster_sha256":"{poster_sha}",
          "poster_mime_type":"image/jpeg",
          "keyframes":[{{"index":0,"sha256":"{keyframe_sha}","mime_type":"image/jpeg","t_ms":0,"kind":"scene"}}]
        }}"#,
        segment_sha = segment.sha256,
        audio_sha = audio.sha256,
        poster_sha = poster.sha256,
        keyframe_sha = keyframe.sha256,
    );
    let manifest = db::insert_attachment(
        &conn,
        &key,
        &app_dir,
        manifest_json.as_bytes(),
        "application/x.secondloop.video+json",
    )
    .expect("manifest");

    let derivations =
        db::ensure_video_manifest_derivations(&conn, &key, &app_dir, &manifest.sha256)
            .expect("backfill derivations");
    assert_eq!(derivations.len(), 5);

    let roles: Vec<String> = derivations.iter().map(|item| item.role.clone()).collect();
    assert!(roles.iter().any(|role| role == "root_manifest"));
    assert!(roles.iter().any(|role| role == "proxy_segment"));
    assert!(roles.iter().any(|role| role == "extracted_audio"));
    assert!(roles.iter().any(|role| role == "poster"));
    assert!(roles.iter().any(|role| role == "keyframe"));
}

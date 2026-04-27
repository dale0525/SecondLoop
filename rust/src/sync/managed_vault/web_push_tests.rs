use super::*;

#[test]
fn web_push_prepare_and_apply_stay_local_only() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    let db_key = [7u8; 32];
    let sync_key = [9u8; 32];
    let base_url = "http://127.0.0.1:9";
    let vault_id = "vault-1";
    let conversation =
        crate::db::create_conversation(&conn, &db_key, "web").expect("create conversation");
    crate::db::insert_message(&conn, &db_key, &conversation.id, "user", "hello from web")
        .expect("insert message");

    let batch_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare web push batch");
    let batch: serde_json::Value = serde_json::from_str(&batch_json).expect("batch json");
    assert_eq!(batch["has_ops"].as_bool(), Some(true));
    assert_eq!(batch["request"]["base_global_seq"].as_i64(), Some(0));
    assert!(batch["request"]["batch_id"]
        .as_str()
        .is_some_and(|value| !value.is_empty()));
    let op_count = batch["op_count"].as_u64().expect("op count");
    assert!(op_count > 0);
    let response_json = serde_json::json!({
        "generation_id": "generation-1",
        "accepted": op_count,
        "committed_from_seq": 1,
        "committed_to_seq": op_count,
        "remote_latest_global_seq": op_count,
    })
    .to_string();
    let applied_json =
        apply_web_push_response(&conn, base_url, vault_id, &batch_json, &response_json)
            .expect("apply web push response");
    let applied: serde_json::Value = serde_json::from_str(&applied_json).expect("applied json");
    assert_eq!(applied["accepted"].as_u64(), Some(op_count));

    let next_batch_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare next web push batch");
    let next_batch: serde_json::Value =
        serde_json::from_str(&next_batch_json).expect("next batch json");
    assert_eq!(next_batch["has_ops"].as_bool(), Some(false));
}

#[test]
fn web_push_batch_exposes_attachment_media_action_and_upload_body() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    let db_key = [7u8; 32];
    let sync_key = [9u8; 32];
    let base_url = "http://127.0.0.1:9";
    let vault_id = "vault-1";
    let attachment =
        crate::db::insert_attachment(&conn, &db_key, dir.path(), b"web attachment", "image/png")
            .expect("insert attachment");

    let batch_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare web push batch");
    let batch: serde_json::Value = serde_json::from_str(&batch_json).expect("batch json");
    let media_actions = batch["media_actions"].as_array().expect("media actions");
    assert_eq!(media_actions.len(), 1);
    assert_eq!(media_actions[0]["kind"].as_str(), Some("attachment_upload"));
    assert_eq!(
        media_actions[0]["sha256"].as_str(),
        Some(attachment.sha256.as_str())
    );
    assert_eq!(
        media_actions[0]["remote_id"].as_str(),
        Some(attachment.sha256.as_str())
    );
    assert_eq!(media_actions[0]["mime_type"].as_str(), Some("image/png"));

    let upload_json = prepare_web_push_media_upload(
        &conn,
        &db_key,
        &sync_key,
        base_url,
        vault_id,
        &media_actions[0].to_string(),
        WebPushMediaPhase::Batch,
    )
    .expect("prepare upload body");
    let upload: serde_json::Value = serde_json::from_str(&upload_json).expect("upload json");
    assert_eq!(upload["has_body"].as_bool(), Some(true));
    assert_eq!(
        upload["remote_id"].as_str(),
        Some(attachment.sha256.as_str())
    );
    assert_eq!(upload["mime_type"].as_str(), Some("image/png"));
    assert!(upload["ciphertext_b64"]
        .as_str()
        .is_some_and(|value| !value.is_empty()));
    assert!(upload["byte_len"].as_u64().is_some_and(|value| value > 0));
}

#[test]
fn web_push_fresh_device_media_completion_skips_repeat_uploads() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    let db_key = [7u8; 32];
    let sync_key = [9u8; 32];
    let base_url = "http://127.0.0.1:9";
    let vault_id = "vault-1";
    let attachment = crate::db::insert_attachment(
        &conn,
        &db_key,
        dir.path(),
        b"fresh device attachment",
        "image/png",
    )
    .expect("insert attachment");
    let device_id = super::super::super::get_or_create_device_id(&conn).expect("device id");
    conn.execute(
        r#"UPDATE oplog SET device_id = 'remote-device', seq = 1 WHERE device_id = ?1"#,
        params![device_id],
    )
    .expect("seed remote device op");
    let batch_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare fresh device batch");
    let batch: serde_json::Value = serde_json::from_str(&batch_json).expect("batch json");
    assert_eq!(batch["has_ops"].as_bool(), Some(false));
    assert_eq!(batch["media_phase"].as_str(), Some("fresh_device"));
    let media_actions = batch["media_actions"].as_array().expect("media actions");
    assert_eq!(media_actions.len(), 1);
    assert_eq!(
        media_actions[0]["remote_id"].as_str(),
        Some(attachment.sha256.as_str())
    );
    complete_web_push_media_batch(&conn, &db_key, base_url, vault_id, &batch_json)
        .expect("complete fresh device media");
    let next_batch_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare next batch");
    let next_batch: serde_json::Value =
        serde_json::from_str(&next_batch_json).expect("next batch json");
    assert_eq!(next_batch["has_ops"].as_bool(), Some(false));
    assert_eq!(next_batch["media_phase"].as_str(), Some("none"));
    assert_eq!(
        next_batch["media_actions"]
            .as_array()
            .expect("next media actions")
            .len(),
        0
    );
}

#[test]
fn web_push_fresh_device_media_partial_success_skips_uploaded_items() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    let db_key = [7u8; 32];
    let sync_key = [9u8; 32];
    let base_url = "http://127.0.0.1:9";
    let vault_id = "vault-1";
    crate::db::insert_attachment(
        &conn,
        &db_key,
        dir.path(),
        b"fresh device attachment one",
        "image/png",
    )
    .expect("insert attachment one");
    crate::db::insert_attachment(
        &conn,
        &db_key,
        dir.path(),
        b"fresh device attachment two",
        "image/png",
    )
    .expect("insert attachment two");
    let device_id = super::super::super::get_or_create_device_id(&conn).expect("device id");
    let row_ids: Vec<i64> = {
        let mut stmt = conn
            .prepare(r#"SELECT rowid FROM oplog WHERE device_id = ?1 ORDER BY seq ASC"#)
            .expect("prepare oplog rows");
        stmt.query_map(params![device_id], |row| row.get(0))
            .expect("query oplog rows")
            .collect::<std::result::Result<Vec<_>, _>>()
            .expect("collect oplog rows")
    };
    for (index, row_id) in row_ids.iter().enumerate() {
        conn.execute(
            r#"UPDATE oplog SET device_id = 'remote-device', seq = ?1 WHERE rowid = ?2"#,
            params![index as i64 + 1, row_id],
        )
        .expect("seed remote device op");
    }

    let batch_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare fresh device batch");
    let batch: serde_json::Value = serde_json::from_str(&batch_json).expect("batch json");
    assert_eq!(batch["has_ops"].as_bool(), Some(false));
    assert_eq!(batch["media_phase"].as_str(), Some("fresh_device"));
    let media_actions = batch["media_actions"].as_array().expect("media actions");
    assert_eq!(media_actions.len(), 2);
    let uploaded_remote_id = media_actions[0]["remote_id"]
        .as_str()
        .expect("uploaded remote id")
        .to_string();

    record_web_push_media_result(
        &conn,
        base_url,
        vault_id,
        &media_actions[0].to_string(),
        true,
        None,
    )
    .expect("record first success");

    let retry_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare retry batch");
    let retry_batch: serde_json::Value =
        serde_json::from_str(&retry_json).expect("retry batch json");
    assert_eq!(retry_batch["has_ops"].as_bool(), Some(false));
    assert_eq!(retry_batch["media_phase"].as_str(), Some("fresh_device"));
    let retry_actions = retry_batch["media_actions"]
        .as_array()
        .expect("retry media actions");
    assert_eq!(retry_actions.len(), 1);
    assert_ne!(
        retry_actions[0]["remote_id"].as_str(),
        Some(uploaded_remote_id.as_str())
    );

    record_web_push_media_result(
        &conn,
        base_url,
        vault_id,
        &retry_actions[0].to_string(),
        true,
        None,
    )
    .expect("record retry success");
    complete_web_push_media_batch(&conn, &db_key, base_url, vault_id, &retry_json)
        .expect("complete retry batch");
    let done_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare done batch");
    let done_batch: serde_json::Value = serde_json::from_str(&done_json).expect("done batch json");
    assert_eq!(done_batch["media_phase"].as_str(), Some("none"));
    assert_eq!(
        done_batch["media_actions"]
            .as_array()
            .expect("done media actions")
            .len(),
        0
    );
}

#[test]
fn web_push_limits_repair_media_actions_per_batch() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    let db_key = [7u8; 32];
    let sync_key = [9u8; 32];
    let base_url = "http://127.0.0.1:9";
    let vault_id = "vault-1";
    let scope_id = super::super::runtime::scope_id(base_url, vault_id);
    for index in 0..9 {
        crate::sync::blob_repair::enqueue_blob_repair(
            &conn,
            &scope_id,
            crate::sync::blob_repair::BlobRepairKind::UploadAttachment {
                sha256: format!("repair-sha-{index}"),
            },
        )
        .expect("enqueue repair");
    }
    let batch_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare repair batch");
    let batch: serde_json::Value = serde_json::from_str(&batch_json).expect("batch json");
    assert_eq!(batch["has_ops"].as_bool(), Some(false));
    assert_eq!(batch["media_phase"].as_str(), Some("repairs"));
    assert_eq!(
        batch["media_actions"]
            .as_array()
            .expect("media actions")
            .len(),
        8
    );
}

#[test]
fn web_push_batch_prepares_video_manifest_derivations_once() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    let db_key = [7u8; 32];
    let sync_key = [9u8; 32];
    let base_url = "http://127.0.0.1:9";
    let vault_id = "vault-1";
    let segment = crate::db::insert_attachment(&conn, &db_key, dir.path(), b"segment", "video/mp4")
        .expect("insert segment");
    let manifest_payload = serde_json::json!({
        "schema": "secondloop.video_manifest.v2",
        "video_sha256": segment.sha256.as_str(),
        "video_mime_type": "video/mp4",
        "video_segments": [
            {
                "index": 0,
                "sha256": segment.sha256.as_str(),
                "mime_type": "video/mp4"
            }
        ]
    });
    let manifest = crate::db::insert_attachment(
        &conn,
        &db_key,
        dir.path(),
        manifest_payload.to_string().as_bytes(),
        "application/x.secondloop.video+json",
    )
    .expect("insert manifest");
    assert!(
        crate::db::list_attachment_derivations_by_root(&conn, &manifest.sha256)
            .expect("initial derivations")
            .is_empty()
    );
    let _ = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
        .expect("prepare batch");
    let derivations = crate::db::list_attachment_derivations_by_root(&conn, &manifest.sha256)
        .expect("prepared derivations");
    let roles: std::collections::BTreeSet<_> =
        derivations.iter().map(|item| item.role.as_str()).collect();
    assert!(roles.contains("root_manifest"));
    assert!(roles.contains("proxy_segment"));
}

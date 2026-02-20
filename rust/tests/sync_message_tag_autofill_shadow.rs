use rusqlite::{params, OptionalExtension};
use secondloop_rust::auth;
use secondloop_rust::crypto::{decrypt_bytes, derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_pull_message_insert_generates_shadow_suggested_tag_event() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create conversation A");
    let message_a = db::insert_message(
        &conn_a,
        &key_a,
        &conv_a.id,
        "user",
        "work roadmap and planning notes",
    )
    .expect("insert message A");

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

    let suggested =
        db::list_message_suggested_tags(&conn_b, &key_b, &message_a.id).expect("suggested tags");
    let job_status: Option<(String, Option<String>)> = conn_b
        .query_row(
            r#"SELECT status, last_error FROM message_tag_autofill_jobs WHERE message_id = ?1"#,
            params![message_a.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .expect("job status");
    let event_count: i64 = conn_b
        .query_row(
            r#"SELECT COUNT(*) FROM message_tag_autofill_events WHERE message_id = ?1"#,
            params![message_a.id],
            |row| row.get(0),
        )
        .expect("event count");
    assert!(
        suggested.iter().any(|value| value == "work"),
        "expected `work` in sync-pull suggestions, got: {suggested:?}, job_status: {job_status:?}, event_count: {event_count}"
    );

    let message_tags = db::list_message_tags(&conn_b, &key_b, &message_a.id).expect("message tags");
    assert!(
        message_tags.iter().any(|tag| tag.name == "work"),
        "expected sync-pull to auto-apply `work`, got: {message_tags:?}"
    );

    let applied_event_count: i64 = conn_b
        .query_row(
            r#"SELECT COUNT(*) FROM message_tag_autofill_events WHERE message_id = ?1 AND applied = 1"#,
            params![message_a.id],
            |row| row.get(0),
        )
        .expect("applied event count");
    assert!(
        applied_event_count > 0,
        "expected sync-pull message insert to produce applied autofill event"
    );
}

#[test]
fn sync_pull_attachment_annotation_reprocesses_autofill_for_linked_message() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create conversation A");
    let message_a = db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "receipt scan #8271")
        .expect("insert message A");
    let attachment_a = db::insert_attachment(&conn_a, &key_a, &app_dir_a, b"img", "image/png")
        .expect("attachment A");
    db::link_attachment_to_message(&conn_a, &key_a, &message_a.id, &attachment_a.sha256)
        .expect("link attachment A");
    db::mark_attachment_annotation_ok(
        &conn_a,
        &key_a,
        &attachment_a.sha256,
        "und",
        "vision.v1",
        &serde_json::json!({
            "suggested_tags": ["finance"]
        }),
        1_700_000_100_000,
    )
    .expect("mark annotation A");

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

    let suggested =
        db::list_message_suggested_tags(&conn_b, &key_b, &message_a.id).expect("suggested tags");
    assert!(
        suggested.iter().any(|value| value == "finance"),
        "expected `finance` in sync-pull suggestions, got: {suggested:?}"
    );

    let finance_event_count: i64 = conn_b
        .query_row(
            r#"SELECT COUNT(*) FROM message_tag_autofill_events WHERE message_id = ?1 AND candidate_tag = 'finance'"#,
            params![message_a.id],
            |row| row.get(0),
        )
        .expect("finance event count");
    assert!(
        finance_event_count > 0,
        "expected annotation sync to trigger finance autofill event"
    );

    let message_tags = db::list_message_tags(&conn_b, &key_b, &message_a.id).expect("message tags");
    assert!(
        message_tags.is_empty(),
        "shadow mode should not auto-apply from sync annotation"
    );
}

#[test]
fn sync_pull_message_set_insert_fallback_runs_autofill() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create conversation A");

    let message_a = db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "draft note")
        .expect("insert message A");
    db::edit_message(
        &conn_a,
        &key_a,
        &message_a.id,
        "work weekly review and next steps",
    )
    .expect("edit message A");

    let mut stmt = conn_a
        .prepare(r#"SELECT op_id, op_json FROM oplog ORDER BY seq ASC"#)
        .expect("prepare oplog query");
    let mut rows = stmt.query([]).expect("query oplog rows");
    let mut insert_op_ids = Vec::<String>::new();
    while let Some(row) = rows.next().expect("next oplog row") {
        let op_id: String = row.get(0).expect("op id");
        let blob: Vec<u8> = row.get(1).expect("op blob");
        let aad = format!("oplog.op_json:{op_id}");
        let plaintext = decrypt_bytes(&key_a, &blob, aad.as_bytes()).expect("decrypt op");
        let op: serde_json::Value = serde_json::from_slice(&plaintext).expect("parse op");

        if op.get("type").and_then(|v| v.as_str()) == Some("message.insert.v1")
            && op
                .get("payload")
                .and_then(|v| v.get("message_id"))
                .and_then(|v| v.as_str())
                == Some(message_a.id.as_str())
        {
            insert_op_ids.push(op_id);
        }
    }
    assert_eq!(
        insert_op_ids.len(),
        1,
        "expected exactly one message.insert op"
    );
    for op_id in insert_op_ids {
        conn_a
            .execute(r#"DELETE FROM oplog WHERE op_id = ?1"#, params![op_id])
            .expect("delete message insert op");
    }

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

    let messages_b = db::list_messages(&conn_b, &key_b, &conv_a.id).expect("list messages B");
    assert!(
        messages_b
            .iter()
            .any(|m| m.id == message_a.id && m.content.contains("work")),
        "expected message from message.set fallback to be materialized"
    );

    let suggested =
        db::list_message_suggested_tags(&conn_b, &key_b, &message_a.id).expect("suggested tags");
    assert!(
        suggested.iter().any(|value| value == "work"),
        "expected `work` in message.set fallback suggestions, got: {suggested:?}"
    );

    let message_tags = db::list_message_tags(&conn_b, &key_b, &message_a.id).expect("message tags");
    assert!(
        message_tags.iter().any(|tag| tag.name == "work"),
        "expected message.set fallback to auto-apply `work`, got: {message_tags:?}"
    );

    let applied_event_count: i64 = conn_b
        .query_row(
            r#"SELECT COUNT(*) FROM message_tag_autofill_events WHERE message_id = ?1 AND applied = 1"#,
            params![message_a.id],
            |row| row.get(0),
        )
        .expect("applied event count");
    assert!(
        applied_event_count > 0,
        "expected message.set fallback to produce applied autofill event"
    );
}

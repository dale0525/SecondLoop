use secondloop_rust::auth;
use secondloop_rust::crypto::{decrypt_bytes, KdfParams};
use secondloop_rust::db;

fn setup() -> (tempfile::TempDir, [u8; 32], rusqlite::Connection) {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");
    (temp_dir, key, conn)
}

#[test]
fn checklist_suggestions_can_be_generated_applied_and_dismissed() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            "Draft launch post".to_string(),
            "Share with team".to_string(),
        ],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate suggestions");
    assert_eq!(generated.len(), 2);
    assert!(generated.iter().all(|item| item.state == "pending"));

    let applied =
        db::apply_todo_checklist_suggestions(&conn, &key, "todo_1", &[generated[0].id.clone()])
            .expect("apply suggestion");
    assert_eq!(applied.len(), 1);
    assert_eq!(applied[0].content, "Draft launch post");

    db::dismiss_todo_checklist_suggestions(&conn, &key, "todo_1", &[generated[1].id.clone()])
        .expect("dismiss suggestion");

    let suggestions =
        db::list_todo_checklist_suggestions(&conn, &key, "todo_1").expect("list suggestions");
    assert_eq!(suggestions.len(), 2);
    assert!(suggestions.iter().any(|item| item.state == "applied"));
    assert!(suggestions.iter().any(|item| item.state == "dismissed"));

    let checklist_items =
        db::list_todo_checklist_items(&conn, &key, "todo_1").expect("list checklist items");
    assert_eq!(checklist_items.len(), 1);
    assert_eq!(checklist_items[0].content, "Draft launch post");
}

#[test]
fn regenerate_skips_dismissed_and_applied_duplicates() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let initial = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            " Draft launch post ".to_string(),
            "Share with team".to_string(),
        ],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate initial");

    db::apply_todo_checklist_suggestions(&conn, &key, "todo_1", &[initial[0].id.clone()])
        .expect("apply initial");
    db::dismiss_todo_checklist_suggestions(&conn, &key, "todo_1", &[initial[1].id.clone()])
        .expect("dismiss initial");

    let regenerated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            "draft launch post".to_string(),
            "share with team".to_string(),
            "Collect approvals".to_string(),
        ],
        "cloud",
        Some("gen_2"),
    )
    .expect("regenerate suggestions");

    assert_eq!(regenerated.len(), 1);
    assert_eq!(regenerated[0].content, "Collect approvals");
    assert_eq!(regenerated[0].state, "pending");
}

#[test]
fn generated_suggestion_sort_order_stays_contiguous_after_skips() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            "".to_string(),
            "Draft launch post".to_string(),
            " draft launch post ".to_string(),
            "Share with team".to_string(),
        ],
        "cloud",
        Some("gen_gapped_sort"),
    )
    .expect("generate suggestions");

    assert_eq!(generated.len(), 2);
    assert_eq!(generated[0].sort_order, 0);
    assert_eq!(generated[1].sort_order, 1);
}

#[test]
fn dismiss_all_marks_all_pending_suggestions_dismissed() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            "Draft launch post".to_string(),
            "Share with team".to_string(),
        ],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate suggestions");

    db::dismiss_all_todo_checklist_suggestions(&conn, &key, "todo_1")
        .expect("dismiss all suggestions");

    let suggestions =
        db::list_todo_checklist_suggestions(&conn, &key, "todo_1").expect("list suggestions");
    assert_eq!(suggestions.len(), 2);
    assert!(suggestions
        .iter()
        .all(|item| item.state == "dismissed" && item.dismissed_at_ms.is_some()));
}

#[test]
fn generate_suggestions_rolls_back_when_oplog_insert_fails() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    conn.execute_batch(
        r#"
CREATE TEMP TRIGGER fail_checklist_suggestion_oplog_insert
BEFORE INSERT ON oplog
BEGIN
  SELECT RAISE(ABORT, 'forced oplog failure');
END;
"#,
    )
    .expect("create trigger");

    let err = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            "Draft launch post".to_string(),
            "Share with team".to_string(),
        ],
        "cloud",
        Some("gen_rollback"),
    )
    .expect_err("upsert should fail");
    assert!(err.to_string().contains("forced oplog failure"));

    let suggestions =
        db::list_todo_checklist_suggestions(&conn, &key, "todo_1").expect("list suggestions");
    assert!(suggestions.is_empty());
}

#[test]
fn dismiss_suggestions_rolls_back_when_oplog_insert_fails() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            "Draft launch post".to_string(),
            "Share with team".to_string(),
        ],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate suggestions");

    conn.execute_batch(
        r#"
CREATE TEMP TRIGGER fail_checklist_dismiss_oplog_insert
BEFORE INSERT ON oplog
BEGIN
  SELECT RAISE(ABORT, 'forced oplog failure');
END;
"#,
    )
    .expect("create trigger");

    let err = db::dismiss_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[generated[0].id.clone(), generated[1].id.clone()],
    )
    .expect_err("dismiss should fail");
    assert!(err.to_string().contains("forced oplog failure"));

    let suggestions =
        db::list_todo_checklist_suggestions(&conn, &key, "todo_1").expect("list suggestions");
    assert!(suggestions.iter().all(|item| item.state == "pending"));
    assert!(suggestions
        .iter()
        .all(|item| item.dismissed_at_ms.is_none()));
}

#[test]
fn checklist_generate_suggestions_succeeds_inside_active_transaction() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    conn.execute_batch("BEGIN;")
        .expect("begin outer transaction");
    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            "Draft launch post".to_string(),
            "Share with team".to_string(),
        ],
        "cloud",
        Some("gen_nested"),
    )
    .expect("generate suggestions inside transaction");
    conn.execute_batch("COMMIT;")
        .expect("commit outer transaction");

    assert_eq!(generated.len(), 2);
}

#[test]
fn checklist_apply_suggestions_succeeds_inside_active_transaction() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &["Draft launch post".to_string()],
        "cloud",
        Some("gen_apply_nested"),
    )
    .expect("generate suggestions");

    conn.execute_batch("BEGIN;")
        .expect("begin outer transaction");
    let applied =
        db::apply_todo_checklist_suggestions(&conn, &key, "todo_1", &[generated[0].id.clone()])
            .expect("apply suggestions inside transaction");
    conn.execute_batch("COMMIT;")
        .expect("commit outer transaction");

    assert_eq!(applied.len(), 1);
    assert_eq!(applied[0].content, "Draft launch post");
}

#[test]
fn checklist_dismiss_suggestions_succeeds_inside_active_transaction() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &["Share with team".to_string()],
        "cloud",
        Some("gen_dismiss_nested"),
    )
    .expect("generate suggestions");

    conn.execute_batch("BEGIN;")
        .expect("begin outer transaction");
    db::dismiss_todo_checklist_suggestions(&conn, &key, "todo_1", &[generated[0].id.clone()])
        .expect("dismiss suggestions inside transaction");
    conn.execute_batch("COMMIT;")
        .expect("commit outer transaction");

    let suggestions =
        db::list_todo_checklist_suggestions(&conn, &key, "todo_1").expect("list suggestions");
    assert_eq!(suggestions[0].state, "dismissed");
}

#[test]
fn dismiss_suggestions_skips_oplog_when_no_rows_change() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &["Share with team".to_string()],
        "cloud",
        Some("gen_skip_noop_dismiss"),
    )
    .expect("generate suggestions");

    db::dismiss_todo_checklist_suggestions(&conn, &key, "todo_1", &[generated[0].id.clone()])
        .expect("dismiss suggestion once");

    let oplog_before: i64 = conn
        .query_row("SELECT COUNT(*) FROM oplog", [], |row| row.get(0))
        .expect("count oplog before noop dismiss");

    db::dismiss_todo_checklist_suggestions(&conn, &key, "todo_1", &[generated[0].id.clone()])
        .expect("dismiss suggestion twice");

    let oplog_after: i64 = conn
        .query_row("SELECT COUNT(*) FROM oplog", [], |row| row.get(0))
        .expect("count oplog after noop dismiss");

    assert_eq!(oplog_after, oplog_before);
}

#[test]
fn generate_suggestions_uses_consistent_timestamps_per_batch() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let raw_suggestions = (0..512)
        .map(|index| format!("Suggestion {index}"))
        .collect::<Vec<_>>();

    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &raw_suggestions,
        "cloud",
        Some("gen_consistent_batch_time"),
    )
    .expect("generate suggestions");

    assert_eq!(generated.len(), raw_suggestions.len());
    let created_at_ms = generated[0].created_at_ms;
    let updated_at_ms = generated[0].updated_at_ms;
    assert!(generated
        .iter()
        .all(|item| item.created_at_ms == created_at_ms));
    assert!(generated
        .iter()
        .all(|item| item.updated_at_ms == updated_at_ms));
}

#[test]
fn deleting_applied_checklist_item_reverts_suggestion_to_pending() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &["Draft launch post".to_string()],
        "cloud",
        Some("gen_revert_applied"),
    )
    .expect("generate suggestions");

    let applied =
        db::apply_todo_checklist_suggestions(&conn, &key, "todo_1", &[generated[0].id.clone()])
            .expect("apply suggestion");
    assert_eq!(applied.len(), 1);

    db::delete_todo_checklist_item(&conn, &key, &applied[0].id)
        .expect("delete applied checklist item");

    let suggestions =
        db::list_todo_checklist_suggestions(&conn, &key, "todo_1").expect("list suggestions");
    assert_eq!(suggestions.len(), 1);
    assert_eq!(suggestions[0].state, "pending");
    assert_eq!(suggestions[0].applied_checklist_item_id, None);

    let regenerated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &["draft launch post".to_string()],
        "cloud",
        Some("gen_revert_applied_again"),
    )
    .expect("regenerate suggestions after delete");
    assert!(regenerated.is_empty());

    let reapplied =
        db::apply_todo_checklist_suggestions(&conn, &key, "todo_1", &[generated[0].id.clone()])
            .expect("reapply suggestion");
    assert_eq!(reapplied.len(), 1);
    assert_eq!(reapplied[0].content, "Draft launch post");
}

#[test]
fn apply_suggestions_uses_consistent_timestamps_per_batch() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            "Draft launch post".to_string(),
            "Share with team".to_string(),
        ],
        "cloud",
        Some("gen_apply_batch_time"),
    )
    .expect("generate suggestions");

    let applied = db::apply_todo_checklist_suggestions(
        &conn,
        &key,
        "todo_1",
        &[generated[0].id.clone(), generated[1].id.clone()],
    )
    .expect("apply suggestions");
    assert_eq!(applied.len(), 2);

    let suggestions =
        db::list_todo_checklist_suggestions(&conn, &key, "todo_1").expect("list suggestions");
    let applied_suggestions = suggestions
        .iter()
        .filter(|item| item.state == "applied")
        .collect::<Vec<_>>();
    assert_eq!(applied_suggestions.len(), 2);
    let updated_at_ms = applied_suggestions[0].updated_at_ms;
    assert!(applied_suggestions
        .iter()
        .all(|item| item.updated_at_ms == updated_at_ms));

    let mut stmt = conn
        .prepare(r#"SELECT op_id, op_json FROM oplog ORDER BY seq ASC"#)
        .expect("prepare oplog query");
    let mut rows = stmt.query([]).expect("query oplog");
    let mut apply_ts = Vec::new();
    while let Some(row) = rows.next().expect("next oplog row") {
        let op_id: String = row.get(0).expect("op_id");
        let op_json_blob: Vec<u8> = row.get(1).expect("op_json");
        let plaintext = decrypt_bytes(
            &key,
            &op_json_blob,
            format!("oplog.op_json:{op_id}").as_bytes(),
        )
        .expect("decrypt oplog payload");
        let value: serde_json::Value =
            serde_json::from_slice(&plaintext).expect("parse oplog json");
        if value["type"].as_str() == Some("todo.checklist_suggestion.apply.v1") {
            apply_ts.push(value["ts_ms"].as_i64().expect("apply ts_ms"));
        }
    }

    assert_eq!(apply_ts.len(), 2);
    assert!(apply_ts.iter().all(|ts| *ts == apply_ts[0]));

    let item_create_ts = applied
        .iter()
        .map(|item| {
            let mut stmt = conn
                .prepare(r#"SELECT op_id, op_json FROM oplog ORDER BY seq ASC"#)
                .expect("prepare per-item oplog query");
            let mut rows = stmt.query([]).expect("query per-item oplog");
            while let Some(row) = rows.next().expect("next per-item oplog row") {
                let op_id: String = row.get(0).expect("per-item op_id");
                let op_json_blob: Vec<u8> = row.get(1).expect("per-item op_json");
                let plaintext = decrypt_bytes(
                    &key,
                    &op_json_blob,
                    format!("oplog.op_json:{op_id}").as_bytes(),
                )
                .expect("decrypt per-item oplog payload");
                let value: serde_json::Value =
                    serde_json::from_slice(&plaintext).expect("parse per-item oplog json");
                if value["type"].as_str() == Some("todo.checklist_item.upsert.v1")
                    && value["payload"]["item_id"].as_str() == Some(item.id.as_str())
                {
                    return value["ts_ms"].as_i64().expect("item upsert ts_ms");
                }
            }
            panic!("missing checklist item upsert oplog for {}", item.id);
        })
        .collect::<Vec<_>>();
    assert_eq!(item_create_ts.len(), 2);
    assert!(item_create_ts.iter().all(|ts| *ts <= apply_ts[0]));
}

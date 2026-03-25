use rusqlite::Connection;
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn migration_from_v35_repairs_missing_manual_override_followup_column() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");

    let conn = db::open(&app_dir).expect("open latest db");
    drop(conn);

    let db_path = app_dir.join("secondloop.sqlite3");
    let legacy = Connection::open(&db_path).expect("open raw db");
    legacy
        .execute_batch(
            r#"
DROP INDEX IF EXISTS idx_todo_followup_generation_jobs_status_due;
DROP TABLE IF EXISTS todo_followup_generation_jobs;
CREATE TABLE todo_followup_generation_jobs (
  todo_id TEXT PRIMARY KEY,
  trigger_kind TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at_ms INTEGER,
  last_error TEXT,
  include_manual_followups INTEGER NOT NULL DEFAULT 0,
  task_type_hint TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE
);
CREATE INDEX idx_todo_followup_generation_jobs_status_due
  ON todo_followup_generation_jobs(status, next_retry_at_ms, updated_at_ms);
PRAGMA user_version = 35;
"#,
        )
        .expect("downgrade followup jobs table to legacy v35 shape");
    drop(legacy);

    let conn = db::open(&app_dir).expect("re-open migrated db");

    let cols: Vec<String> = conn
        .prepare("PRAGMA table_info(todo_followup_generation_jobs)")
        .expect("prepare table_info")
        .query_map([], |row| row.get(1))
        .expect("query table_info")
        .map(|row| row.expect("table_info row"))
        .collect();
    assert!(cols.iter().any(|col| col == "manual_override_followup"));

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "修复登录页闪退",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::enqueue_todo_followup_generation_job(
        &conn,
        "todo_1",
        "manual_regenerate",
        true,
        Some("execution"),
        100,
    )
    .expect("enqueue manual override job after migration");

    let job = db::find_todo_followup_generation_job(&conn, "todo_1")
        .expect("find job")
        .expect("job should exist");
    assert!(job.manual_override_followup);
    assert_eq!(job.task_type_hint.as_deref(), Some("execution"));
}

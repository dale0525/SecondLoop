use rusqlite::params;
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn open_repairs_todo_manual_nudge_columns_when_version_is_already_35() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");

    let conn = db::open(&app_dir).expect("open db");
    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Legacy todo",
        None,
        "open",
        None,
        None,
        None,
        None,
        Some(1),
        Some(-1),
    )
    .expect("upsert todo");
    drop(conn);

    let db_path = app_dir.join("secondloop.sqlite3");
    let legacy = rusqlite::Connection::open(&db_path).expect("open raw sqlite");
    legacy
        .execute_batch(
            r#"
ALTER TABLE todos RENAME TO todos_old;
CREATE TABLE todos (
  id TEXT PRIMARY KEY,
  title BLOB NOT NULL,
  due_at_ms INTEGER,
  status TEXT NOT NULL,
  source_entry_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  review_stage INTEGER,
  next_review_at_ms INTEGER,
  last_review_at_ms INTEGER,
  needs_embedding INTEGER
);
INSERT INTO todos (
  id,
  title,
  due_at_ms,
  status,
  source_entry_id,
  created_at_ms,
  updated_at_ms,
  review_stage,
  next_review_at_ms,
  last_review_at_ms,
  needs_embedding
)
SELECT
  id,
  title,
  due_at_ms,
  status,
  source_entry_id,
  created_at_ms,
  updated_at_ms,
  review_stage,
  next_review_at_ms,
  last_review_at_ms,
  needs_embedding
FROM todos_old;
DROP TABLE todos_old;
CREATE INDEX idx_todos_due_at_ms ON todos(due_at_ms);
CREATE INDEX idx_todos_next_review_at_ms ON todos(next_review_at_ms);
CREATE INDEX idx_todos_status ON todos(status);
PRAGMA user_version = 35;
"#,
        )
        .expect("downgrade todos schema to legacy shape");
    drop(legacy);

    let repaired = db::open(&app_dir).expect("re-open db after schema drift");

    let mut pragma = repaired
        .prepare("PRAGMA table_info(todos)")
        .expect("prepare pragma");
    let columns = pragma
        .query_map([], |row| row.get::<_, String>(1))
        .expect("query pragma")
        .collect::<std::result::Result<Vec<_>, _>>()
        .expect("collect pragma columns");

    assert!(columns.contains(&"manual_importance_nudge_score".to_string()));
    assert!(columns.contains(&"manual_urgency_nudge_score".to_string()));

    let todos = db::list_todos(&repaired, &key).expect("list todos after repair");
    assert_eq!(todos.len(), 1);
    assert_eq!(todos[0].id, "todo_1");
    assert_eq!(todos[0].title, "Legacy todo");
    assert_eq!(todos[0].manual_importance_nudge_score, Some(0));
    assert_eq!(todos[0].manual_urgency_nudge_score, Some(0));

    let (importance, urgency): (i64, i64) = repaired
        .query_row(
            "SELECT manual_importance_nudge_score, manual_urgency_nudge_score FROM todos WHERE id = ?1",
            params!["todo_1"],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read repaired manual nudge columns");
    assert_eq!(importance, 0);
    assert_eq!(urgency, 0);

    let updated = db::upsert_todo(
        &repaired,
        &key,
        "todo_1",
        "Legacy todo",
        None,
        "open",
        None,
        None,
        None,
        None,
        Some(1),
        Some(-1),
    )
    .expect("upsert todo after repair");
    assert_eq!(updated.manual_importance_nudge_score, Some(1));
    assert_eq!(updated.manual_urgency_nudge_score, Some(-1));
}

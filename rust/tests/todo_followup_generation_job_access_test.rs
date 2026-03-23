use secondloop_rust::api::core;
use secondloop_rust::api::todo_followup_generation;
use secondloop_rust::auth;
use secondloop_rust::crypto;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

fn setup() -> (tempfile::TempDir, [u8; 32], rusqlite::Connection) {
    let temp_dir = tempfile::tempdir().expect("temp dir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    (temp_dir, key, conn)
}

#[test]
fn due_job_api_overfetches_until_it_finds_accessible_jobs() {
    let (temp_dir, key, conn) = setup();
    let app_dir = temp_dir
        .path()
        .join("secondloop")
        .to_string_lossy()
        .into_owned();

    let inaccessible_key = [9u8; 32];
    db::upsert_todo(
        &conn,
        &inaccessible_key,
        "todo_hidden",
        "Secret todo",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert hidden todo");
    db::enqueue_todo_followup_generation_job(&conn, "todo_hidden", "auto_create", None, 90)
        .expect("enqueue hidden job");

    db::upsert_todo(
        &conn,
        &key,
        "todo_visible",
        "Visible todo",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert visible todo");
    db::enqueue_todo_followup_generation_job(&conn, "todo_visible", "auto_create", None, 100)
        .expect("enqueue visible job");

    let due = core::db_list_due_todo_followup_generation_jobs(app_dir, key.to_vec(), 200, 1)
        .expect("list visible due jobs");

    assert_eq!(due.len(), 1);
    assert_eq!(due[0].todo_id, "todo_visible");
}

#[test]
fn due_job_api_surfaces_todo_read_errors_instead_of_silently_skipping_jobs() {
    let (temp_dir, key, conn) = setup();
    let app_dir = temp_dir
        .path()
        .join("secondloop")
        .to_string_lossy()
        .into_owned();

    db::upsert_todo(
        &conn,
        &key,
        "todo_corrupt",
        "Corrupt todo",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");
    db::enqueue_todo_followup_generation_job(&conn, "todo_corrupt", "auto_create", None, 100)
        .expect("enqueue job");

    let invalid_title_blob =
        crypto::encrypt_bytes(&key, &[0xFF], b"todo.title").expect("encrypt invalid utf8 title");
    conn.execute(
        "UPDATE todos SET title = ?1 WHERE id = ?2",
        rusqlite::params![invalid_title_blob, "todo_corrupt"],
    )
    .expect("store invalid utf8 title blob");

    let err = core::db_list_due_todo_followup_generation_jobs(app_dir, key.to_vec(), 200, 1)
        .expect_err("corrupt todo should surface as an error");

    assert!(err.to_string().contains("utf-8") || err.to_string().contains("todo"));
}

#[test]
fn auto_due_job_api_returns_visible_auto_jobs_without_scanning_manual_backlog() {
    let (temp_dir, key, conn) = setup();
    let app_dir = temp_dir
        .path()
        .join("secondloop")
        .to_string_lossy()
        .into_owned();

    db::upsert_todo(
        &conn,
        &key,
        "todo_manual",
        "Manual todo",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert manual todo");
    db::enqueue_todo_followup_generation_job(&conn, "todo_manual", "manual_regenerate", None, 90)
        .expect("enqueue manual job");

    db::upsert_todo(
        &conn,
        &key,
        "todo_auto",
        "Auto todo",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert auto todo");
    db::enqueue_todo_followup_generation_job(&conn, "todo_auto", "auto_create", None, 100)
        .expect("enqueue auto job");

    let due = todo_followup_generation::db_list_due_auto_todo_followup_generation_jobs(
        app_dir,
        key.to_vec(),
        200,
        1,
    )
    .expect("list visible auto due jobs");

    assert_eq!(due.len(), 1);
    assert_eq!(due[0].todo_id, "todo_auto");
    assert_eq!(due[0].trigger_kind, "auto_create");
}

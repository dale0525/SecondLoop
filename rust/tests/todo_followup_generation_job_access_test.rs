use secondloop_rust::api::core;
use secondloop_rust::auth;
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

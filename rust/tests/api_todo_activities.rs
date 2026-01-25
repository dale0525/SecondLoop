use secondloop_rust::api::core;
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;

#[test]
fn api_todo_activities_roundtrip_smoke() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let key_vec = key.to_vec();

    core::db_upsert_todo(
        app_dir.to_string_lossy().to_string(),
        key_vec.clone(),
        "todo_1".to_string(),
        "周末给狗狗做口粮".to_string(),
        None,
        "open".to_string(),
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    core::db_append_todo_note(
        app_dir.to_string_lossy().to_string(),
        key_vec.clone(),
        "todo_1".to_string(),
        "狗粮做完了".to_string(),
        None,
    )
    .expect("append note");

    core::db_set_todo_status(
        app_dir.to_string_lossy().to_string(),
        key_vec.clone(),
        "todo_1".to_string(),
        "in_progress".to_string(),
        None,
    )
    .expect("set status");

    let activities = core::db_list_todo_activities(
        app_dir.to_string_lossy().to_string(),
        key_vec,
        "todo_1".to_string(),
    )
    .expect("list activities");
    assert_eq!(activities.len(), 2);
}

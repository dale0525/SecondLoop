use secondloop_rust::{api::core, db};

#[test]
fn reset_rejects_cross_table_mixed_deferred_keys() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let first_key = [3u8; 32];
    let second_key = [4u8; 32];
    let conversation =
        db::create_conversation(&conn, &first_key, "first").expect("seed conversation");
    db::insert_message(
        &conn,
        &second_key,
        &conversation.id,
        "user",
        "second-key message",
    )
    .expect("seed mixed-key message");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        first_key.to_vec(),
    );

    let error = result.expect_err("mixed table keys should be rejected");
    assert!(
        error.to_string().contains("invalid key"),
        "unexpected error: {error}"
    );
    let conn = db::open(dir.path()).expect("reopen db");
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM messages", [], |row| row.get(0))
        .expect("count messages");
    assert_eq!(count, 1);
}

#[test]
fn reset_allows_missing_auth_with_valid_tag_only_deferred_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let key = [5u8; 32];
    db::upsert_tag(&conn, &key, "Project Alpha").expect("seed tag");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    assert!(
        result.is_ok(),
        "valid tag-only deferred key should allow reset without auth.json: {result:?}"
    );
}

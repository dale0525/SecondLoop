use anyhow::Result;
use rusqlite::params;
use secondloop_rust::auth;
use secondloop_rust::crypto::{decrypt_bytes, derive_root_key, encrypt_bytes, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_todo_upsert_same_updated_at_prefers_later_seq() {
    run_sync_todo_upsert_same_updated_at_prefers_later_seq().expect("test should succeed");
}

fn run_sync_todo_upsert_same_updated_at_prefers_later_seq() -> Result<()> {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTodoUpdatedAtTie";

    let temp_a = tempfile::tempdir()?;
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a = auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test())?;
    let conn_a = db::open(&app_dir_a)?;

    db::upsert_todo(
        &conn_a,
        &key_a,
        "todo:seed",
        "Sync tie check",
        Some(1_730_808_000_000),
        "open",
        None,
        None,
        None,
        None,
    )?;
    db::set_todo_status(&conn_a, &key_a, "todo:seed", "done", None)?;

    let mut todo_upserts = read_todo_upsert_ops(&conn_a, &key_a, "todo:seed")?;
    assert!(
        todo_upserts.len() >= 2,
        "expected at least 2 todo.upsert ops"
    );

    let first_updated_at = todo_upserts[0]
        .2
        .get("payload")
        .and_then(|v| v.get("updated_at_ms"))
        .and_then(|v| v.as_i64())
        .expect("first todo.upsert updated_at_ms");

    for (op_id, _seq, op) in todo_upserts.iter_mut().skip(1) {
        op["payload"]["updated_at_ms"] = serde_json::Value::from(first_updated_at);
        let plaintext = serde_json::to_vec(op)?;
        let aad = format!("oplog.op_json:{op_id}");
        let blob = encrypt_bytes(&key_a, &plaintext, aad.as_bytes())?;
        conn_a.execute(
            "UPDATE oplog SET op_json = ?2 WHERE op_id = ?1",
            params![op_id.as_str(), blob],
        )?;
    }

    let seed_a = db::get_todo(&conn_a, &key_a, "todo:seed")?;
    assert_eq!(seed_a.status, "done");

    let temp_b = tempfile::tempdir()?;
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b = auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test())?;
    let conn_b = db::open(&app_dir_b)?;

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync-todo-updated-at-tie",
        &KdfParams::for_test(),
    )?;

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root)?;
    assert!(pushed > 0);

    let pulled = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root)?;
    assert!(pulled > 0);

    let seed_b = db::get_todo(&conn_b, &key_b, "todo:seed")?;
    assert_eq!(seed_b.status, "done");

    Ok(())
}

fn read_todo_upsert_ops(
    conn: &rusqlite::Connection,
    key: &[u8; 32],
    todo_id: &str,
) -> Result<Vec<(String, i64, serde_json::Value)>> {
    let mut stmt = conn.prepare(
        r#"SELECT op_id, seq, op_json
           FROM oplog
           ORDER BY seq ASC"#,
    )?;
    let mut rows = stmt.query([])?;

    let mut out = Vec::<(String, i64, serde_json::Value)>::new();
    while let Some(row) = rows.next()? {
        let op_id: String = row.get(0)?;
        let seq: i64 = row.get(1)?;
        let blob: Vec<u8> = row.get(2)?;

        let aad = format!("oplog.op_json:{op_id}");
        let plaintext = decrypt_bytes(key, &blob, aad.as_bytes())?;
        let op: serde_json::Value = serde_json::from_slice(&plaintext)?;

        let op_type = op.get("type").and_then(|v| v.as_str()).unwrap_or_default();
        if op_type != "todo.upsert.v1" {
            continue;
        }

        let op_todo_id = op
            .get("payload")
            .and_then(|v| v.get("todo_id"))
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        if op_todo_id != todo_id {
            continue;
        }

        out.push((op_id, seq, op));
    }

    Ok(out)
}

fn todo_checklist_item_content_aad_for_sync(item_id: &str) -> Vec<u8> {
    format!("todo_checklist_item.content:{item_id}").into_bytes()
}

fn todo_checklist_item_deleted_at_key(item_id: &str) -> String {
    format!("todo_checklist_item.deleted_at:{item_id}")
}

fn todo_checklist_item_sort_override_key(item_id: &str) -> String {
    format!("todo_checklist_item.sort_order_override:{item_id}")
}

fn todo_checklist_item_sort_override_updated_at_key(item_id: &str) -> String {
    format!("todo_checklist_item.sort_order_updated_at:{item_id}")
}

fn clear_todo_checklist_item_kv(conn: &Connection, key: &str) -> Result<()> {
    let _ = conn.execute(r#"DELETE FROM kv WHERE key = ?1"#, params![key])?;
    Ok(())
}

fn apply_todo_checklist_item_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let item_id = payload["item_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo.checklist_item.upsert.v1 missing item_id"))?;
    let todo_id = payload["todo_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo.checklist_item.upsert.v1 missing todo_id"))?;
    let content = payload["content"]
        .as_str()
        .ok_or_else(|| anyhow!("todo.checklist_item.upsert.v1 missing content"))?;
    let is_done = payload["is_done"]
        .as_bool()
        .ok_or_else(|| anyhow!("todo.checklist_item.upsert.v1 missing is_done"))?;
    let incoming_sort_order = payload["sort_order"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo.checklist_item.upsert.v1 missing sort_order"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo.checklist_item.upsert.v1 missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo.checklist_item.upsert.v1 missing updated_at_ms"))?;

    let deleted_at_key = todo_checklist_item_deleted_at_key(item_id);
    let existing_deleted_at_ms = kv_get_i64(conn, &deleted_at_key)?.unwrap_or(0);
    if existing_deleted_at_ms > 0 && updated_at_ms <= existing_deleted_at_ms {
        return Ok(());
    }

    let sort_override_updated_at = kv_get_i64(
        conn,
        &todo_checklist_item_sort_override_updated_at_key(item_id),
    )?
    .unwrap_or(0);
    let sort_order = if sort_override_updated_at > updated_at_ms {
        kv_get_i64(conn, &todo_checklist_item_sort_override_key(item_id))?
            .unwrap_or(incoming_sort_order)
    } else {
        incoming_sort_order
    };
    let effective_updated_at_ms = updated_at_ms.max(sort_override_updated_at);

    let existing_updated_at_ms: Option<i64> = conn
        .query_row(
            r#"SELECT updated_at_ms FROM todo_checklist_items WHERE id = ?1"#,
            params![item_id],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(existing_updated_at_ms) = existing_updated_at_ms {
        if effective_updated_at_ms < existing_updated_at_ms {
            return Ok(());
        }
    }

    if existing_deleted_at_ms > 0 && effective_updated_at_ms > existing_deleted_at_ms {
        clear_todo_checklist_item_kv(conn, &deleted_at_key)?;
    }

    let content_blob = encrypt_bytes(
        db_key,
        content.as_bytes(),
        &todo_checklist_item_content_aad_for_sync(item_id),
    )?;

    let todo_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM todos WHERE id = ?1"#,
            params![todo_id],
            |row| row.get(0),
        )
        .optional()?;
    if todo_exists.is_none() {
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let upsert_result = conn.execute(
        r#"
INSERT INTO todo_checklist_items(id, todo_id, content, is_done, sort_order, created_at_ms, updated_at_ms)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
ON CONFLICT(id) DO UPDATE SET
  todo_id = CASE
    WHEN excluded.updated_at_ms >= todo_checklist_items.updated_at_ms THEN excluded.todo_id
    ELSE todo_checklist_items.todo_id
  END,
  content = CASE
    WHEN excluded.updated_at_ms >= todo_checklist_items.updated_at_ms THEN excluded.content
    ELSE todo_checklist_items.content
  END,
  is_done = CASE
    WHEN excluded.updated_at_ms >= todo_checklist_items.updated_at_ms THEN excluded.is_done
    ELSE todo_checklist_items.is_done
  END,
  sort_order = CASE
    WHEN excluded.updated_at_ms >= todo_checklist_items.updated_at_ms THEN excluded.sort_order
    ELSE todo_checklist_items.sort_order
  END,
  created_at_ms = min(todo_checklist_items.created_at_ms, excluded.created_at_ms),
  updated_at_ms = max(todo_checklist_items.updated_at_ms, excluded.updated_at_ms)
"#,
        params![
            item_id,
            todo_id,
            content_blob,
            if is_done { 1 } else { 0 },
            sort_order,
            created_at_ms,
            effective_updated_at_ms,
        ],
    );

    if todo_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    upsert_result?;
    Ok(())
}

fn apply_todo_checklist_item_delete(
    conn: &Connection,
    payload: &serde_json::Value,
) -> Result<()> {
    let item_id = payload["item_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo.checklist_item.delete.v1 missing item_id"))?;
    let deleted_at_ms = payload["deleted_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo.checklist_item.delete.v1 missing deleted_at_ms"))?;

    let deleted_at_key = todo_checklist_item_deleted_at_key(item_id);
    let existing_deleted_at_ms = kv_get_i64(conn, &deleted_at_key)?.unwrap_or(0);
    if deleted_at_ms < existing_deleted_at_ms {
        return Ok(());
    }

    let _ = conn.execute(
        r#"DELETE FROM todo_checklist_items WHERE id = ?1"#,
        params![item_id],
    )?;
    kv_set_i64(conn, &deleted_at_key, deleted_at_ms)?;
    clear_todo_checklist_item_kv(conn, &todo_checklist_item_sort_override_key(item_id))?;
    clear_todo_checklist_item_kv(
        conn,
        &todo_checklist_item_sort_override_updated_at_key(item_id),
    )?;
    Ok(())
}

fn apply_todo_checklist_item_reorder(
    conn: &Connection,
    payload: &serde_json::Value,
) -> Result<()> {
    let todo_id = payload["todo_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo.checklist_item.reorder.v1 missing todo_id"))?;
    let ordered_item_ids = payload["ordered_item_ids"]
        .as_array()
        .ok_or_else(|| anyhow!("todo.checklist_item.reorder.v1 missing ordered_item_ids"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo.checklist_item.reorder.v1 missing updated_at_ms"))?;

    for (index, item_id) in ordered_item_ids.iter().enumerate() {
        let item_id = item_id
            .as_str()
            .ok_or_else(|| anyhow!("todo.checklist_item.reorder.v1 item id must be string"))?;

        let deleted_at_key = todo_checklist_item_deleted_at_key(item_id);
        let existing_deleted_at_ms = kv_get_i64(conn, &deleted_at_key)?.unwrap_or(0);
        if existing_deleted_at_ms > 0 && updated_at_ms <= existing_deleted_at_ms {
            continue;
        }

        let existing_updated_at_ms: Option<i64> = conn
            .query_row(
                r#"SELECT updated_at_ms
                   FROM todo_checklist_items
                   WHERE id = ?1 AND todo_id = ?2"#,
                params![item_id, todo_id],
                |row| row.get(0),
            )
            .optional()?;
        if let Some(existing_updated_at_ms) = existing_updated_at_ms {
            if updated_at_ms < existing_updated_at_ms {
                continue;
            }
        }

        kv_set_i64(
            conn,
            &todo_checklist_item_sort_override_key(item_id),
            index as i64,
        )?;
        kv_set_i64(
            conn,
            &todo_checklist_item_sort_override_updated_at_key(item_id),
            updated_at_ms,
        )?;

        let _ = conn.execute(
            r#"UPDATE todo_checklist_items
               SET sort_order = ?3,
                   updated_at_ms = ?4
               WHERE id = ?1
                 AND todo_id = ?2
                 AND updated_at_ms <= ?4"#,
            params![item_id, todo_id, index as i64, updated_at_ms],
        )?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn test_conn() -> (tempfile::TempDir, Connection, [u8; 32]) {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        (dir, conn, [7; 32])
    }

    fn apply_test_todo(conn: &Connection, key: &[u8; 32], todo_id: &str) {
        apply_op(
            conn,
            key,
            &json!({
                "type": "todo.upsert.v1",
                "payload": {
                    "todo_id": todo_id,
                    "title": "Checklist sync todo",
                    "status": "open",
                    "due_at_ms": serde_json::Value::Null,
                    "source_entry_id": serde_json::Value::Null,
                    "created_at_ms": 10,
                    "updated_at_ms": 10,
                    "review_stage": 0,
                    "next_review_at_ms": serde_json::Value::Null,
                    "last_review_at_ms": serde_json::Value::Null,
                    "manual_importance_nudge_score": 0,
                    "manual_urgency_nudge_score": 0,
                }
            }),
        )
        .expect("apply todo");
    }

    #[test]
    fn apply_checklist_item_upsert_creates_item_for_existing_todo() {
        let (_dir, conn, key) = test_conn();
        apply_test_todo(&conn, &key, "todo-1");

        apply_op(
            &conn,
            &key,
            &json!({
                "type": "todo.checklist_item.upsert.v1",
                "payload": {
                    "item_id": "item-1",
                    "todo_id": "todo-1",
                    "content": "Confirm device-two sync",
                    "is_done": false,
                    "sort_order": 0,
                    "created_at_ms": 20,
                    "updated_at_ms": 20,
                }
            }),
        )
        .expect("apply checklist upsert");

        let items =
            crate::db::list_todo_checklist_items(&conn, &key, "todo-1").expect("list checklist");
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].id, "item-1");
        assert_eq!(items[0].content, "Confirm device-two sync");
        assert_eq!(items[0].sort_order, 0);
        assert!(!items[0].is_done);
    }

    #[test]
    fn apply_checklist_item_delete_blocks_stale_upsert() {
        let (_dir, conn, key) = test_conn();
        apply_test_todo(&conn, &key, "todo-1");

        apply_op(
            &conn,
            &key,
            &json!({
                "type": "todo.checklist_item.upsert.v1",
                "payload": {
                    "item_id": "item-1",
                    "todo_id": "todo-1",
                    "content": "Confirm device-two sync",
                    "is_done": false,
                    "sort_order": 0,
                    "created_at_ms": 20,
                    "updated_at_ms": 20,
                }
            }),
        )
        .expect("apply checklist upsert");

        apply_op(
            &conn,
            &key,
            &json!({
                "type": "todo.checklist_item.delete.v1",
                "payload": {
                    "item_id": "item-1",
                    "todo_id": "todo-1",
                    "deleted_at_ms": 30,
                }
            }),
        )
        .expect("apply checklist delete");

        apply_op(
            &conn,
            &key,
            &json!({
                "type": "todo.checklist_item.upsert.v1",
                "payload": {
                    "item_id": "item-1",
                    "todo_id": "todo-1",
                    "content": "stale content",
                    "is_done": true,
                    "sort_order": 9,
                    "created_at_ms": 20,
                    "updated_at_ms": 25,
                }
            }),
        )
        .expect("apply stale checklist upsert");

        let items =
            crate::db::list_todo_checklist_items(&conn, &key, "todo-1").expect("list checklist");
        assert!(items.is_empty());
    }

    #[test]
    fn apply_checklist_reorder_before_upserts_preserves_latest_sort_order() {
        let (_dir, conn, key) = test_conn();
        apply_test_todo(&conn, &key, "todo-1");

        apply_op(
            &conn,
            &key,
            &json!({
                "type": "todo.checklist_item.reorder.v1",
                "payload": {
                    "todo_id": "todo-1",
                    "ordered_item_ids": ["item-b", "item-a"],
                    "updated_at_ms": 50,
                }
            }),
        )
        .expect("apply checklist reorder");

        apply_op(
            &conn,
            &key,
            &json!({
                "type": "todo.checklist_item.upsert.v1",
                "payload": {
                    "item_id": "item-a",
                    "todo_id": "todo-1",
                    "content": "A",
                    "is_done": false,
                    "sort_order": 0,
                    "created_at_ms": 20,
                    "updated_at_ms": 20,
                }
            }),
        )
        .expect("apply checklist upsert a");
        apply_op(
            &conn,
            &key,
            &json!({
                "type": "todo.checklist_item.upsert.v1",
                "payload": {
                    "item_id": "item-b",
                    "todo_id": "todo-1",
                    "content": "B",
                    "is_done": false,
                    "sort_order": 1,
                    "created_at_ms": 20,
                    "updated_at_ms": 20,
                }
            }),
        )
        .expect("apply checklist upsert b");

        let items =
            crate::db::list_todo_checklist_items(&conn, &key, "todo-1").expect("list checklist");
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].id, "item-b");
        assert_eq!(items[0].sort_order, 0);
        assert_eq!(items[1].id, "item-a");
        assert_eq!(items[1].sort_order, 1);
    }
}

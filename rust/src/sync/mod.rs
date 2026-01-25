use std::collections::{BTreeMap, BTreeSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64_URL;
use base64::Engine as _;
use rusqlite::{params, Connection, OptionalExtension};

use crate::crypto::{decrypt_bytes, encrypt_bytes};

pub mod localdir;
pub mod managed_vault;
pub mod webdav;

#[derive(Debug)]
pub struct NotFound {
    pub path: String,
}

impl std::fmt::Display for NotFound {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "not found: {}", self.path)
    }
}

impl std::error::Error for NotFound {}

pub trait RemoteStore: Send + Sync {
    fn target_id(&self) -> &str;
    fn mkdir_all(&self, path: &str) -> Result<()>;
    fn list(&self, dir: &str) -> Result<Vec<String>>;
    fn get(&self, path: &str) -> Result<Vec<u8>>;
    fn put(&self, path: &str, bytes: Vec<u8>) -> Result<()>;
    fn delete(&self, path: &str) -> Result<()>;
}

static INMEM_NEXT_ID: AtomicU64 = AtomicU64::new(1);

pub struct InMemoryRemoteStore {
    target_id: String,
    dirs: Mutex<BTreeSet<String>>,
    files: Mutex<BTreeMap<String, Vec<u8>>>,
}

impl InMemoryRemoteStore {
    pub fn new() -> Self {
        let id = INMEM_NEXT_ID.fetch_add(1, Ordering::Relaxed);
        Self {
            target_id: format!("inmem:{id}"),
            dirs: Mutex::new(BTreeSet::new()),
            files: Mutex::new(BTreeMap::new()),
        }
    }
}

impl Default for InMemoryRemoteStore {
    fn default() -> Self {
        Self::new()
    }
}

fn normalize_dir(path: &str) -> String {
    let trimmed = path.trim_matches('/');
    if trimmed.is_empty() {
        return "/".to_string();
    }
    format!("/{trimmed}/")
}

fn normalize_file(path: &str) -> String {
    let trimmed = path.trim_matches('/');
    format!("/{trimmed}")
}

fn sync_scope_id(remote: &impl RemoteStore, remote_root_dir: &str) -> String {
    let scope = format!("{}|{remote_root_dir}", remote.target_id());
    B64_URL.encode(scope.as_bytes())
}

impl RemoteStore for InMemoryRemoteStore {
    fn target_id(&self) -> &str {
        &self.target_id
    }

    fn mkdir_all(&self, path: &str) -> Result<()> {
        let dir = normalize_dir(path);
        let mut dirs = self.dirs.lock().map_err(|_| anyhow!("poisoned lock"))?;
        // Add all parent dirs.
        let mut cur = "/".to_string();
        dirs.insert(cur.clone());
        for part in dir.trim_matches('/').split('/') {
            if part.is_empty() {
                continue;
            }
            cur.push_str(part);
            cur.push('/');
            dirs.insert(cur.clone());
        }
        Ok(())
    }

    fn list(&self, dir: &str) -> Result<Vec<String>> {
        let dir = normalize_dir(dir);
        let dirs = self.dirs.lock().map_err(|_| anyhow!("poisoned lock"))?;
        let files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;

        if !dirs.contains(&dir) {
            return Ok(vec![]);
        }

        let mut out: BTreeSet<String> = BTreeSet::new();

        for d in dirs.iter() {
            if d == &dir {
                continue;
            }
            if let Some(rest) = d.strip_prefix(&dir) {
                if rest.is_empty() {
                    continue;
                }
                let mut parts = rest.split('/').filter(|p| !p.is_empty());
                if let Some(first) = parts.next() {
                    out.insert(format!("{dir}{first}/"));
                }
            }
        }

        for f in files.keys() {
            if let Some(rest) = f.strip_prefix(&dir) {
                if rest.is_empty() {
                    continue;
                }
                let mut parts = rest.split('/').filter(|p| !p.is_empty());
                if let Some(first) = parts.next() {
                    if parts.next().is_none() {
                        out.insert(format!("{dir}{first}"));
                    } else {
                        out.insert(format!("{dir}{first}/"));
                    }
                }
            }
        }

        Ok(out.into_iter().collect())
    }

    fn get(&self, path: &str) -> Result<Vec<u8>> {
        let path = normalize_file(path);
        let files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;
        files
            .get(&path)
            .cloned()
            .ok_or_else(|| NotFound { path }.into())
    }

    fn put(&self, path: &str, bytes: Vec<u8>) -> Result<()> {
        let path = normalize_file(path);
        let mut files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;
        files.insert(path, bytes);
        Ok(())
    }

    fn delete(&self, path: &str) -> Result<()> {
        if path.ends_with('/') {
            let dir = normalize_dir(path);
            if dir == "/" {
                return Err(anyhow!("refusing to delete root dir"));
            }

            let mut dirs = self.dirs.lock().map_err(|_| anyhow!("poisoned lock"))?;
            let mut files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;

            if !dirs.contains(&dir) {
                return Err(NotFound { path: dir }.into());
            }

            let to_remove: Vec<String> = files
                .keys()
                .filter(|k| k.starts_with(&dir))
                .cloned()
                .collect();
            for key in to_remove {
                files.remove(&key);
            }

            let dirs_to_remove: Vec<String> = dirs
                .iter()
                .filter(|d| d.starts_with(&dir))
                .cloned()
                .collect();
            for d in dirs_to_remove {
                dirs.remove(&d);
            }

            Ok(())
        } else {
            let file = normalize_file(path);
            let mut files = self.files.lock().map_err(|_| anyhow!("poisoned lock"))?;
            if files.remove(&file).is_none() {
                return Err(NotFound { path: file }.into());
            }
            Ok(())
        }
    }
}

pub fn clear_remote_root(remote: &impl RemoteStore, remote_root: &str) -> Result<()> {
    let remote_root_dir = normalize_dir(remote_root);
    if remote_root_dir == "/" {
        return Err(anyhow!("refusing to clear remote root '/'"));
    }

    match remote.delete(&remote_root_dir) {
        Ok(()) => Ok(()),
        Err(e) if e.is::<NotFound>() => Ok(()),
        Err(e) => Err(e),
    }
}

pub fn push(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
) -> Result<u64> {
    let device_id = get_or_create_device_id(conn)?;
    let remote_root_dir = normalize_dir(remote_root);
    let scope_id = sync_scope_id(remote, &remote_root_dir);
    let ops_dir = format!("{remote_root_dir}{device_id}/ops/");
    remote.mkdir_all(&ops_dir)?;

    let last_pushed_key = format!("sync.last_pushed_seq:{scope_id}");
    let last_pushed_seq = kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);

    fn push_ops_after(
        conn: &Connection,
        db_key: &[u8; 32],
        sync_key: &[u8; 32],
        remote: &impl RemoteStore,
        device_id: &str,
        ops_dir: &str,
        after_seq: i64,
    ) -> Result<(u64, i64)> {
        let mut stmt = conn.prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1 AND seq > ?2
               ORDER BY seq ASC"#,
        )?;

        let mut rows = stmt.query(params![device_id, after_seq])?;
        let mut pushed: u64 = 0;
        let mut max_seq = after_seq;

        while let Some(row) = rows.next()? {
            let op_id: String = row.get(0)?;
            let seq: i64 = row.get(1)?;
            let op_json_blob: Vec<u8> = row.get(2)?;

            let plaintext = decrypt_bytes(
                db_key,
                &op_json_blob,
                format!("oplog.op_json:{op_id}").as_bytes(),
            )?;
            let file_blob = encrypt_bytes(
                sync_key,
                &plaintext,
                format!("sync.ops:{device_id}:{seq}").as_bytes(),
            )?;

            let file_path = format!("{ops_dir}op_{seq}.json");
            remote.put(&file_path, file_blob)?;

            pushed += 1;
            if seq > max_seq {
                max_seq = seq;
            }
        }

        Ok((pushed, max_seq))
    }

    let (pushed, max_seq) = push_ops_after(
        conn,
        db_key,
        sync_key,
        remote,
        &device_id,
        &ops_dir,
        last_pushed_seq,
    )?;

    if pushed > 0 {
        kv_set_i64(conn, &last_pushed_key, max_seq)?;
        return Ok(pushed);
    }

    // If the remote target was cleared/reset (e.g. user switches directories then comes back),
    // our cursor may say "up to date" while the remote no longer has the last pushed file.
    if last_pushed_seq > 0 {
        let last_path = format!("{ops_dir}op_{last_pushed_seq}.json");
        match remote.get(&last_path) {
            Ok(_) => {}
            Err(e) if e.is::<NotFound>() => {
                let (re_pushed, re_max_seq) =
                    push_ops_after(conn, db_key, sync_key, remote, &device_id, &ops_dir, 0)?;
                if re_pushed > 0 {
                    kv_set_i64(conn, &last_pushed_key, re_max_seq)?;
                }
                return Ok(re_pushed);
            }
            Err(e) => return Err(e),
        }
    }

    Ok(0)
}

pub fn pull(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
) -> Result<u64> {
    let local_device_id = get_or_create_device_id(conn)?;
    let remote_root_dir = normalize_dir(remote_root);
    let scope_id = sync_scope_id(remote, &remote_root_dir);

    let mut applied: u64 = 0;

    let device_dirs = remote.list(&remote_root_dir)?;
    for device_dir in device_dirs {
        if !device_dir.ends_with('/') {
            continue;
        }
        let Some(device_id) = device_id_from_child_dir(&remote_root_dir, &device_dir) else {
            continue;
        };
        if device_id == local_device_id {
            continue;
        }

        let ops_dir = format!("{remote_root_dir}{device_id}/ops/");

        let last_pulled_key = format!("sync.last_pulled_seq:{scope_id}:{device_id}");
        let last_pulled_seq = kv_get_i64(conn, &last_pulled_key)?.unwrap_or(0);

        let mut new_last_pulled = last_pulled_seq;
        let mut seq = last_pulled_seq + 1;

        let mut tried_discover_start_seq = false;
        loop {
            let path = format!("{ops_dir}op_{seq}.json");
            let blob = match remote.get(&path) {
                Ok(blob) => blob,
                Err(e) if e.is::<NotFound>() => {
                    // If remote ops were pruned/reset, a new device might not have `op_1.json`.
                    // Try to discover the first available seq once (without relying exclusively on listing).
                    if !tried_discover_start_seq && last_pulled_seq == 0 && seq == 1 {
                        tried_discover_start_seq = true;
                        if let Some(start_seq) =
                            discover_first_available_seq(remote, &ops_dir, 500)?
                        {
                            seq = start_seq;
                            continue;
                        }
                    }
                    break;
                }
                Err(e) => return Err(e),
            };
            let plaintext = decrypt_bytes(
                sync_key,
                &blob,
                format!("sync.ops:{device_id}:{seq}").as_bytes(),
            )?;
            let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
            let op_id = op_json["op_id"]
                .as_str()
                .ok_or_else(|| anyhow!("sync op missing op_id"))?
                .to_string();

            let seen: Option<i64> = conn
                .query_row(
                    r#"SELECT 1 FROM oplog WHERE op_id = ?1"#,
                    params![op_id.as_str()],
                    |row| row.get(0),
                )
                .optional()?;
            if seen.is_none() {
                apply_op(conn, db_key, &op_json)?;
                insert_remote_oplog(conn, db_key, &plaintext, &op_json)?;
                applied += 1;
            }

            new_last_pulled = seq;
            seq += 1;
        }

        if new_last_pulled > last_pulled_seq {
            kv_set_i64(conn, &last_pulled_key, new_last_pulled)?;
        }
    }

    Ok(applied)
}

fn discover_first_available_seq(
    remote: &impl RemoteStore,
    ops_dir: &str,
    probe_limit: i64,
) -> Result<Option<i64>> {
    fn parse_seq_from_path(ops_dir: &str, entry: &str) -> Option<i64> {
        let rest = entry.strip_prefix(ops_dir)?;
        let rest = rest.strip_prefix("op_")?;
        let rest = rest.strip_suffix(".json")?;
        if rest.is_empty() {
            return None;
        }
        if rest.bytes().any(|b| !b.is_ascii_digit()) {
            return None;
        }
        rest.parse::<i64>().ok()
    }

    // Best effort: use listing if available.
    if let Ok(entries) = remote.list(ops_dir) {
        let mut min_seq: Option<i64> = None;
        for entry in entries {
            let Some(seq) = parse_seq_from_path(ops_dir, &entry) else {
                continue;
            };
            min_seq = Some(match min_seq {
                Some(existing) => existing.min(seq),
                None => seq,
            });
        }
        if min_seq.is_some() {
            return Ok(min_seq);
        }
    }

    // Fallback: probe a small range to avoid depending on listing.
    for seq in 2..=probe_limit {
        let path = format!("{ops_dir}op_{seq}.json");
        match remote.get(&path) {
            Ok(_) => return Ok(Some(seq)),
            Err(e) if e.is::<NotFound>() => continue,
            Err(e) => return Err(e),
        }
    }

    Ok(None)
}

fn get_or_create_device_id(conn: &Connection) -> Result<String> {
    let existing: Option<String> = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .optional()?;

    if let Some(device_id) = existing {
        return Ok(device_id);
    }

    let device_id = uuid::Uuid::new_v4().to_string();
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', ?1)"#,
        params![device_id],
    )?;
    Ok(device_id)
}

fn kv_get_i64(conn: &Connection, key: &str) -> Result<Option<i64>> {
    let value: Option<String> = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = ?1"#,
            params![key],
            |row| row.get(0),
        )
        .optional()?;
    Ok(value.and_then(|v| v.parse::<i64>().ok()))
}

fn kv_set_i64(conn: &Connection, key: &str, value: i64) -> Result<()> {
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![key, value.to_string()],
    )?;
    Ok(())
}

fn device_id_from_child_dir(root_dir: &str, child_dir: &str) -> Option<String> {
    let rest = child_dir.strip_prefix(root_dir)?;
    let rest = rest.strip_suffix('/')?;
    if rest.is_empty() || rest.contains('/') {
        return None;
    }
    Some(rest.to_string())
}

fn insert_remote_oplog(
    conn: &Connection,
    db_key: &[u8; 32],
    op_plaintext_json: &[u8],
    op_json: &serde_json::Value,
) -> Result<()> {
    let op_id = op_json["op_id"]
        .as_str()
        .ok_or_else(|| anyhow!("oplog missing op_id"))?;
    let device_id = op_json["device_id"]
        .as_str()
        .ok_or_else(|| anyhow!("oplog missing device_id"))?;
    let seq = op_json["seq"]
        .as_i64()
        .ok_or_else(|| anyhow!("oplog missing seq"))?;
    let created_at = op_json["ts_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("oplog missing ts_ms"))?;

    let blob = encrypt_bytes(
        db_key,
        op_plaintext_json,
        format!("oplog.op_json:{op_id}").as_bytes(),
    )?;
    conn.execute(
        r#"INSERT OR IGNORE INTO oplog(op_id, device_id, seq, op_json, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![op_id, device_id, seq, blob, created_at],
    )?;
    Ok(())
}

fn apply_op(conn: &Connection, db_key: &[u8; 32], op: &serde_json::Value) -> Result<()> {
    let op_type = op["type"]
        .as_str()
        .ok_or_else(|| anyhow!("sync op missing type"))?;
    match op_type {
        "conversation.upsert.v1" => apply_conversation_upsert(conn, db_key, &op["payload"]),
        "message.insert.v1" => apply_message_insert(conn, db_key, op),
        "message.set.v2" => apply_message_set_v2(conn, db_key, op),
        "todo.upsert.v1" => apply_todo_upsert(conn, db_key, &op["payload"]),
        "todo.activity.append.v1" => apply_todo_activity_append(conn, db_key, &op["payload"]),
        "todo.activity_attachment.link.v1" => {
            apply_todo_activity_attachment_link(conn, db_key, &op["payload"])
        }
        "event.upsert.v1" => apply_event_upsert(conn, db_key, &op["payload"]),
        other => Err(anyhow!("unsupported sync op type: {other}")),
    }
}

fn apply_conversation_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let conversation_id = payload["conversation_id"]
        .as_str()
        .ok_or_else(|| anyhow!("conversation op missing conversation_id"))?;
    let title = payload["title"]
        .as_str()
        .ok_or_else(|| anyhow!("conversation op missing title"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("conversation op missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("conversation op missing updated_at_ms"))?;

    let existing_updated_at: Option<i64> = conn
        .query_row(
            r#"SELECT updated_at FROM conversations WHERE id = ?1"#,
            params![conversation_id],
            |row| row.get(0),
        )
        .optional()?;

    if existing_updated_at.is_none() {
        let title_blob = encrypt_bytes(db_key, title.as_bytes(), b"conversation.title")?;
        conn.execute(
            r#"INSERT INTO conversations(id, title, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)"#,
            params![conversation_id, title_blob, created_at_ms, updated_at_ms],
        )?;
        return Ok(());
    }

    let Some(existing_updated_at) = existing_updated_at else {
        return Ok(());
    };
    if updated_at_ms <= existing_updated_at {
        return Ok(());
    }

    let title_blob = encrypt_bytes(db_key, title.as_bytes(), b"conversation.title")?;
    conn.execute(
        r#"UPDATE conversations SET title = ?2, updated_at = ?3 WHERE id = ?1"#,
        params![conversation_id, title_blob, updated_at_ms],
    )?;
    Ok(())
}

fn apply_todo_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let todo_id = payload["todo_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo op missing todo_id"))?;
    let title = payload["title"]
        .as_str()
        .ok_or_else(|| anyhow!("todo op missing title"))?;
    let status = payload["status"]
        .as_str()
        .ok_or_else(|| anyhow!("todo op missing status"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo op missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo op missing updated_at_ms"))?;

    let due_at_ms = payload["due_at_ms"].as_i64();
    let source_entry_id = payload["source_entry_id"].as_str();
    let review_stage = payload["review_stage"].as_i64();
    let next_review_at_ms = payload["next_review_at_ms"].as_i64();
    let last_review_at_ms = payload["last_review_at_ms"].as_i64();

    let existing_updated_at: Option<i64> = conn
        .query_row(
            r#"SELECT updated_at_ms FROM todos WHERE id = ?1"#,
            params![todo_id],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(existing_updated_at) = existing_updated_at {
        if updated_at_ms <= existing_updated_at {
            return Ok(());
        }
    }

    let title_blob = encrypt_bytes(db_key, title.as_bytes(), b"todo.title")?;
    if existing_updated_at.is_some() {
        conn.execute(
            r#"UPDATE todos
               SET title = ?2,
                   due_at_ms = ?3,
                   status = ?4,
                   source_entry_id = ?5,
                   updated_at_ms = ?6,
                   review_stage = ?7,
                   next_review_at_ms = ?8,
                   last_review_at_ms = ?9
               WHERE id = ?1"#,
            params![
                todo_id,
                title_blob,
                due_at_ms,
                status,
                source_entry_id,
                updated_at_ms,
                review_stage,
                next_review_at_ms,
                last_review_at_ms,
            ],
        )?;
    } else {
        conn.execute(
            r#"INSERT INTO todos(
                 id, title, due_at_ms, status, source_entry_id, created_at_ms, updated_at_ms,
                 review_stage, next_review_at_ms, last_review_at_ms
               )
               VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)"#,
            params![
                todo_id,
                title_blob,
                due_at_ms,
                status,
                source_entry_id,
                created_at_ms,
                updated_at_ms,
                review_stage,
                next_review_at_ms,
                last_review_at_ms,
            ],
        )?;
    }

    Ok(())
}

fn apply_todo_activity_append(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let activity_id = payload["activity_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity op missing activity_id"))?;
    let todo_id = payload["todo_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity op missing todo_id"))?;
    let activity_type = payload["activity_type"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity op missing activity_type"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo activity op missing created_at_ms"))?;

    let from_status = payload["from_status"].as_str();
    let to_status = payload["to_status"].as_str();
    let source_message_id = payload["source_message_id"].as_str();
    let content = payload["content"].as_str();

    let existing: Option<i64> = conn
        .query_row(
            r#"SELECT created_at_ms FROM todo_activities WHERE id = ?1"#,
            params![activity_id],
            |row| row.get(0),
        )
        .optional()?;
    if existing.is_some() {
        return Ok(());
    }

    let content_blob = if let Some(content) = content {
        let aad = format!("todo_activity.content:{activity_id}");
        Some(encrypt_bytes(db_key, content.as_bytes(), aad.as_bytes())?)
    } else {
        None
    };

    let todo_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM todos WHERE id = ?1"#,
            params![todo_id],
            |row| row.get(0),
        )
        .optional()?;
    if todo_exists.is_none() {
        // Avoid hard sync failures due to cross-device ordering. We'll accept an orphan activity
        // temporarily; if the todo arrives later, it will become valid.
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let insert_result = conn.execute(
        r#"INSERT OR IGNORE INTO todo_activities(
             id, todo_id, type, from_status, to_status, content, source_message_id, created_at_ms
           )
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"#,
        params![
            activity_id,
            todo_id,
            activity_type,
            from_status,
            to_status,
            content_blob,
            source_message_id,
            created_at_ms
        ],
    );

    if todo_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    insert_result?;
    Ok(())
}

fn apply_todo_activity_attachment_link(
    conn: &Connection,
    _db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let activity_id = payload["activity_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity attachment op missing activity_id"))?;
    let attachment_sha256 = payload["attachment_sha256"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity attachment op missing attachment_sha256"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo activity attachment op missing created_at_ms"))?;

    let existing: Option<i64> = conn
        .query_row(
            r#"SELECT 1
               FROM todo_activity_attachments
               WHERE activity_id = ?1 AND attachment_sha256 = ?2"#,
            params![activity_id, attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if existing.is_some() {
        return Ok(());
    }

    let activity_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM todo_activities WHERE id = ?1"#,
            params![activity_id],
            |row| row.get(0),
        )
        .optional()?;
    let attachment_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM attachments WHERE sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;

    if activity_exists.is_none() || attachment_exists.is_none() {
        // Avoid hard sync failures due to cross-device ordering. Accept orphan links temporarily;
        // they'll resolve once the activity/attachment arrives.
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let insert_result = conn.execute(
        r#"INSERT OR IGNORE INTO todo_activity_attachments(activity_id, attachment_sha256, created_at_ms)
           VALUES (?1, ?2, ?3)"#,
        params![activity_id, attachment_sha256, created_at_ms],
    );

    if activity_exists.is_none() || attachment_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    insert_result?;
    Ok(())
}

fn apply_event_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let event_id = payload["event_id"]
        .as_str()
        .ok_or_else(|| anyhow!("event op missing event_id"))?;
    let title = payload["title"]
        .as_str()
        .ok_or_else(|| anyhow!("event op missing title"))?;
    let start_at_ms = payload["start_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("event op missing start_at_ms"))?;
    let end_at_ms = payload["end_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("event op missing end_at_ms"))?;
    let tz = payload["tz"]
        .as_str()
        .ok_or_else(|| anyhow!("event op missing tz"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("event op missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("event op missing updated_at_ms"))?;

    let source_entry_id = payload["source_entry_id"].as_str();

    let existing_updated_at: Option<i64> = conn
        .query_row(
            r#"SELECT updated_at_ms FROM events WHERE id = ?1"#,
            params![event_id],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(existing_updated_at) = existing_updated_at {
        if updated_at_ms <= existing_updated_at {
            return Ok(());
        }
    }

    let title_blob = encrypt_bytes(db_key, title.as_bytes(), b"event.title")?;
    if existing_updated_at.is_some() {
        conn.execute(
            r#"UPDATE events
               SET title = ?2,
                   start_at_ms = ?3,
                   end_at_ms = ?4,
                   tz = ?5,
                   source_entry_id = ?6,
                   updated_at_ms = ?7
               WHERE id = ?1"#,
            params![
                event_id,
                title_blob,
                start_at_ms,
                end_at_ms,
                tz,
                source_entry_id,
                updated_at_ms
            ],
        )?;
    } else {
        conn.execute(
            r#"INSERT INTO events(
                 id, title, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms
               )
               VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"#,
            params![
                event_id,
                title_blob,
                start_at_ms,
                end_at_ms,
                tz,
                source_entry_id,
                created_at_ms,
                updated_at_ms
            ],
        )?;
    }

    Ok(())
}

fn apply_message_insert(
    conn: &Connection,
    db_key: &[u8; 32],
    op: &serde_json::Value,
) -> Result<()> {
    let device_id = op["device_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing device_id"))?;
    let seq = op["seq"]
        .as_i64()
        .ok_or_else(|| anyhow!("message op missing seq"))?;
    let payload = &op["payload"];
    let message_id = payload["message_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing message_id"))?;
    let conversation_id = payload["conversation_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing conversation_id"))?;
    let role = payload["role"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing role"))?;
    let content = payload["content"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing content"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("message op missing created_at_ms"))?;
    let is_memory = payload["is_memory"]
        .as_bool()
        .unwrap_or_else(|| role != "assistant");

    let conversation_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM conversations WHERE id = ?1"#,
            params![conversation_id],
            |row| row.get(0),
        )
        .optional()?;
    if conversation_exists.is_none() {
        return Err(anyhow!(
            "missing conversation for message: {conversation_id}"
        ));
    }

    let content_blob = encrypt_bytes(db_key, content.as_bytes(), b"message.content")?;
    conn.execute(
        r#"INSERT OR IGNORE INTO messages
           (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory)
           VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6, ?7, 0, ?8, ?9)"#,
        params![
            message_id,
            conversation_id,
            role,
            content_blob,
            created_at_ms,
            device_id,
            seq,
            if is_memory { 1 } else { 0 },
            if is_memory { 1 } else { 0 }
        ],
    )?;

    // Heuristic for legacy Ask AI flows: when an assistant message is marked non-memory, treat the
    // immediately preceding user message (same device/seq ordering) as non-memory too.
    if role == "assistant" && !is_memory {
        if let Some(prev_seq) = seq.checked_sub(1) {
            let _ = conn.execute(
                r#"UPDATE messages
                   SET is_memory = 0,
                       needs_embedding = 0
                   WHERE conversation_id = ?1
                     AND role = 'user'
                     AND updated_by_device_id = ?2
                     AND updated_by_seq = ?3
                     AND COALESCE(is_memory, 1) != 0"#,
                params![conversation_id, device_id, prev_seq],
            )?;
        }
    }

    conn.execute(
        r#"UPDATE conversations
           SET updated_at = CASE WHEN updated_at < ?2 THEN ?2 ELSE updated_at END
           WHERE id = ?1"#,
        params![conversation_id, created_at_ms],
    )?;

    Ok(())
}

fn message_version_newer(
    incoming_updated_at: i64,
    incoming_device_id: &str,
    incoming_seq: i64,
    existing_updated_at: i64,
    existing_device_id: &str,
    existing_seq: i64,
) -> bool {
    if incoming_updated_at != existing_updated_at {
        return incoming_updated_at > existing_updated_at;
    }
    if incoming_device_id != existing_device_id {
        return incoming_device_id > existing_device_id;
    }
    incoming_seq > existing_seq
}

fn apply_message_set_v2(
    conn: &Connection,
    db_key: &[u8; 32],
    op: &serde_json::Value,
) -> Result<()> {
    let device_id = op["device_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message.set.v2 missing device_id"))?;
    let seq = op["seq"]
        .as_i64()
        .ok_or_else(|| anyhow!("message.set.v2 missing seq"))?;
    let payload = &op["payload"];

    let message_id = payload["message_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message.set.v2 missing message_id"))?;
    let role = payload["role"]
        .as_str()
        .ok_or_else(|| anyhow!("message.set.v2 missing role"))?;
    let content = payload["content"]
        .as_str()
        .ok_or_else(|| anyhow!("message.set.v2 missing content"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("message.set.v2 missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("message.set.v2 missing updated_at_ms"))?;
    let is_deleted = payload["is_deleted"]
        .as_bool()
        .ok_or_else(|| anyhow!("message.set.v2 missing is_deleted"))?;
    let incoming_is_memory = payload["is_memory"].as_bool();

    let payload_conversation_id = payload["conversation_id"].as_str();
    let existing_conversation_id: Option<String> = conn
        .query_row(
            r#"SELECT conversation_id FROM messages WHERE id = ?1"#,
            params![message_id],
            |row| row.get(0),
        )
        .optional()?;
    let conversation_id = match (payload_conversation_id, existing_conversation_id) {
        (Some(id), _) => id.to_string(),
        (None, Some(id)) => id,
        (None, None) => {
            return Err(anyhow!(
                "message.set.v2 missing conversation_id for unknown message: {message_id}"
            ))
        }
    };

    let existing: Option<(i64, String, i64, i64)> = conn
        .query_row(
            r#"SELECT updated_at, updated_by_device_id, updated_by_seq, COALESCE(is_memory, 1)
               FROM messages
               WHERE id = ?1"#,
            params![message_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()?;

    if let Some((existing_updated_at, existing_device_id, existing_seq, existing_is_memory_i64)) =
        existing
    {
        if !message_version_newer(
            updated_at_ms,
            device_id,
            seq,
            existing_updated_at,
            &existing_device_id,
            existing_seq,
        ) {
            return Ok(());
        }

        let is_memory = incoming_is_memory.unwrap_or(existing_is_memory_i64 != 0);
        let content_blob = encrypt_bytes(db_key, content.as_bytes(), b"message.content")?;
        conn.execute(
            r#"UPDATE messages
               SET role = ?2,
                   content = ?3,
                   updated_at = ?4,
                   updated_by_device_id = ?5,
                   updated_by_seq = ?6,
                   is_deleted = ?7,
                   is_memory = ?8,
                   needs_embedding = CASE WHEN ?7 = 0 AND ?8 = 1 THEN 1 ELSE 0 END
               WHERE id = ?1"#,
            params![
                message_id,
                role,
                content_blob,
                updated_at_ms,
                device_id,
                seq,
                if is_deleted { 1 } else { 0 },
                if is_memory { 1 } else { 0 }
            ],
        )?;
    } else {
        let conversation_exists: Option<i64> = conn
            .query_row(
                r#"SELECT 1 FROM conversations WHERE id = ?1"#,
                params![conversation_id.as_str()],
                |row| row.get(0),
            )
            .optional()?;
        if conversation_exists.is_none() {
            return Err(anyhow!(
                "missing conversation for message: {conversation_id}"
            ));
        }

        let content_blob = encrypt_bytes(db_key, content.as_bytes(), b"message.content")?;
        let is_memory = incoming_is_memory.unwrap_or_else(|| role != "assistant");
        let needs_embedding = !is_deleted && is_memory;
        conn.execute(
            r#"INSERT INTO messages
               (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory)
               VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)"#,
            params![
                message_id,
                conversation_id.as_str(),
                role,
                content_blob,
                created_at_ms,
                updated_at_ms,
                device_id,
                seq,
                if is_deleted { 1 } else { 0 },
                if needs_embedding { 1 } else { 0 },
                if is_memory { 1 } else { 0 }
            ],
        )?;
    }

    conn.execute(
        r#"UPDATE conversations
           SET updated_at = CASE WHEN updated_at < ?2 THEN ?2 ELSE updated_at END
           WHERE id = ?1"#,
        params![conversation_id.as_str(), updated_at_ms],
    )?;

    Ok(())
}

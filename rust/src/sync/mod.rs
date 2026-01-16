use std::collections::{BTreeMap, BTreeSet};
use std::sync::Mutex;

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OptionalExtension};

use crate::crypto::{decrypt_bytes, encrypt_bytes};

pub mod webdav;
pub mod localdir;

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
    fn mkdir_all(&self, path: &str) -> Result<()>;
    fn list(&self, dir: &str) -> Result<Vec<String>>;
    fn get(&self, path: &str) -> Result<Vec<u8>>;
    fn put(&self, path: &str, bytes: Vec<u8>) -> Result<()>;
}

#[derive(Default)]
pub struct InMemoryRemoteStore {
    dirs: Mutex<BTreeSet<String>>,
    files: Mutex<BTreeMap<String, Vec<u8>>>,
}

impl InMemoryRemoteStore {
    pub fn new() -> Self {
        Self::default()
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

impl RemoteStore for InMemoryRemoteStore {
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
    let ops_dir = format!("{remote_root_dir}{device_id}/ops/");
    remote.mkdir_all(&ops_dir)?;

    let last_pushed_seq = kv_get_i64(conn, "sync.last_pushed_seq")?.unwrap_or(0);

    let mut stmt = conn.prepare(
        r#"SELECT op_id, seq, op_json
           FROM oplog
           WHERE device_id = ?1 AND seq > ?2
           ORDER BY seq ASC"#,
    )?;

    let mut rows = stmt.query(params![device_id.as_str(), last_pushed_seq])?;
    let mut pushed: u64 = 0;
    let mut max_seq = last_pushed_seq;

    while let Some(row) = rows.next()? {
        let op_id: String = row.get(0)?;
        let seq: i64 = row.get(1)?;
        let op_json_blob: Vec<u8> = row.get(2)?;

        let plaintext =
            decrypt_bytes(db_key, &op_json_blob, format!("oplog.op_json:{op_id}").as_bytes())?;
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

    if pushed > 0 {
        kv_set_i64(conn, "sync.last_pushed_seq", max_seq)?;
    }

    Ok(pushed)
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

        let last_pulled_key = format!("sync.last_pulled_seq:{device_id}");
        let last_pulled_seq = kv_get_i64(conn, &last_pulled_key)?.unwrap_or(0);

        let mut new_last_pulled = last_pulled_seq;
        let mut seq = last_pulled_seq + 1;
        loop {
            let path = format!("{ops_dir}op_{seq}.json");
            let blob = match remote.get(&path) {
                Ok(blob) => blob,
                Err(e) if e.is::<NotFound>() => break,
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

    let blob =
        encrypt_bytes(db_key, op_plaintext_json, format!("oplog.op_json:{op_id}").as_bytes())?;
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
        other => Err(anyhow!("unsupported sync op type: {other}")),
    }
}

fn apply_conversation_upsert(conn: &Connection, db_key: &[u8; 32], payload: &serde_json::Value) -> Result<()> {
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

fn apply_message_insert(conn: &Connection, db_key: &[u8; 32], op: &serde_json::Value) -> Result<()> {
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

    let conversation_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM conversations WHERE id = ?1"#,
            params![conversation_id],
            |row| row.get(0),
        )
        .optional()?;
    if conversation_exists.is_none() {
        return Err(anyhow!("missing conversation for message: {conversation_id}"));
    }

    let content_blob = encrypt_bytes(db_key, content.as_bytes(), b"message.content")?;
    conn.execute(
        r#"INSERT OR IGNORE INTO messages
           (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding)
           VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6, ?7, 0, 1)"#,
        params![
            message_id,
            conversation_id,
            role,
            content_blob,
            created_at_ms,
            device_id,
            seq
        ],
    )?;

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

fn apply_message_set_v2(conn: &Connection, db_key: &[u8; 32], op: &serde_json::Value) -> Result<()> {
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

    let existing: Option<(i64, String, i64)> = conn
        .query_row(
            r#"SELECT updated_at, updated_by_device_id, updated_by_seq
               FROM messages
               WHERE id = ?1"#,
            params![message_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;

    if let Some((existing_updated_at, existing_device_id, existing_seq)) = existing {
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

        let content_blob = encrypt_bytes(db_key, content.as_bytes(), b"message.content")?;
        conn.execute(
            r#"UPDATE messages
               SET role = ?2,
                   content = ?3,
                   updated_at = ?4,
                   updated_by_device_id = ?5,
                   updated_by_seq = ?6,
                   is_deleted = ?7,
                   needs_embedding = CASE WHEN ?7 = 0 THEN 1 ELSE needs_embedding END
               WHERE id = ?1"#,
            params![
                message_id,
                role,
                content_blob,
                updated_at_ms,
                device_id,
                seq,
                if is_deleted { 1 } else { 0 }
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
            return Err(anyhow!("missing conversation for message: {conversation_id}"));
        }

        let content_blob = encrypt_bytes(db_key, content.as_bytes(), b"message.content")?;
        conn.execute(
            r#"INSERT INTO messages
               (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding)
               VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)"#,
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
                if is_deleted { 0 } else { 1 }
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

pub fn upsert_attachment_derivation(
    conn: &Connection,
    root_sha256: &str,
    child_sha256: &str,
    role: &str,
    created_at_ms: i64,
) -> Result<()> {
    let root_sha256 = root_sha256.trim();
    let child_sha256 = child_sha256.trim();
    let role = role.trim();
    if root_sha256.is_empty() {
        return Err(anyhow!("root_sha256 is required"));
    }
    if child_sha256.is_empty() {
        return Err(anyhow!("child_sha256 is required"));
    }
    if role.is_empty() {
        return Err(anyhow!("role is required"));
    }

    conn.execute(
        r#"
INSERT OR IGNORE INTO attachment_derivations(
  root_sha256,
  child_sha256,
  role,
  created_at_ms
)
VALUES (?1, ?2, ?3, ?4)
"#,
        params![root_sha256, child_sha256, role, created_at_ms],
    )?;
    Ok(())
}

fn list_attachment_derivations_by_root_raw(
    conn: &Connection,
    root_sha256: &str,
) -> Result<Vec<AttachmentDerivation>> {
    let root_sha256 = root_sha256.trim();
    if root_sha256.is_empty() {
        return Ok(Vec::new());
    }

    let mut stmt = conn.prepare(
        r#"
SELECT root_sha256, child_sha256, role, created_at_ms
FROM attachment_derivations
WHERE root_sha256 = ?1
ORDER BY created_at_ms ASC, role ASC, child_sha256 ASC
"#,
    )?;

    let rows = stmt.query_map(params![root_sha256], |row| {
        Ok(AttachmentDerivation {
            root_sha256: row.get(0)?,
            child_sha256: row.get(1)?,
            role: row.get(2)?,
            created_at_ms: row.get(3)?,
        })
    })?;

    let mut items = Vec::new();
    for row in rows {
        items.push(row?);
    }
    Ok(items)
}

pub fn ensure_video_manifest_derivations(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    root_sha256: &str,
) -> Result<Vec<AttachmentDerivation>> {
    let root_sha256 = root_sha256.trim();
    if root_sha256.is_empty() {
        return Ok(Vec::new());
    }

    let existing = list_attachment_derivations_by_root_raw(conn, root_sha256)?;
    if !existing.is_empty() {
        return Ok(existing);
    }

    let mime_type: Option<String> = conn
        .query_row(
            r#"SELECT mime_type FROM attachments WHERE sha256 = ?1"#,
            params![root_sha256],
            |row| row.get(0),
        )
        .optional()?;
    let Some(mime_type) = mime_type else {
        return Ok(Vec::new());
    };
    if mime_type.trim() != VIDEO_MANIFEST_MIME {
        return Ok(Vec::new());
    }

    let bytes = read_attachment_bytes(conn, key, app_dir, root_sha256)?;
    let parsed = parse_video_manifest_payload(&bytes)?;
    let created_at_ms = now_ms();

    upsert_attachment_derivation(conn, root_sha256, root_sha256, "root_manifest", created_at_ms)?;

    for segment in parsed.segments {
        upsert_attachment_derivation(
            conn,
            root_sha256,
            &segment.sha256,
            "proxy_segment",
            created_at_ms,
        )?;
    }

    if let Some(audio_sha256) = parsed.audio_sha256 {
        upsert_attachment_derivation(
            conn,
            root_sha256,
            &audio_sha256,
            "extracted_audio",
            created_at_ms,
        )?;
    }

    if let Some(poster_sha256) = parsed.poster_sha256 {
        upsert_attachment_derivation(conn, root_sha256, &poster_sha256, "poster", created_at_ms)?;
    }

    for keyframe in parsed.keyframes {
        upsert_attachment_derivation(
            conn,
            root_sha256,
            &keyframe.sha256,
            "keyframe",
            created_at_ms,
        )?;
    }

    list_attachment_derivations_by_root_raw(conn, root_sha256)
}

pub fn ensure_all_video_manifest_derivations(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
) -> Result<u64> {
    let mut stmt = conn.prepare(
        r#"
SELECT sha256
FROM attachments
WHERE mime_type = ?1
ORDER BY created_at ASC, sha256 ASC
"#,
    )?;
    let rows = stmt.query_map(params![VIDEO_MANIFEST_MIME], |row| row.get::<_, String>(0))?;

    let mut touched = 0u64;
    for row in rows {
        let root_sha256 = row?;
        let derivations = ensure_video_manifest_derivations(conn, key, app_dir, &root_sha256)?;
        if !derivations.is_empty() {
            touched += 1;
        }
    }
    Ok(touched)
}

pub fn list_attachment_derivations_by_root(
    conn: &Connection,
    root_sha256: &str,
) -> Result<Vec<AttachmentDerivation>> {
    list_attachment_derivations_by_root_raw(conn, root_sha256)
}

pub fn list_attachment_derivation_roots_by_child(
    conn: &Connection,
    child_sha256: &str,
) -> Result<Vec<String>> {
    let child_sha256 = child_sha256.trim();
    if child_sha256.is_empty() {
        return Ok(Vec::new());
    }

    let mut stmt = conn.prepare(
        r#"
SELECT DISTINCT root_sha256
FROM attachment_derivations
WHERE child_sha256 = ?1
ORDER BY root_sha256 ASC
"#,
    )?;

    let rows = stmt.query_map(params![child_sha256], |row| row.get::<_, String>(0))?;
    let mut items = Vec::new();
    for row in rows {
        items.push(row?);
    }
    Ok(items)
}

pub fn attachment_derivation_role_for_root_child(
    conn: &Connection,
    root_sha256: &str,
    child_sha256: &str,
) -> Result<Option<String>> {
    let root_sha256 = root_sha256.trim();
    let child_sha256 = child_sha256.trim();
    if root_sha256.is_empty() || child_sha256.is_empty() {
        return Ok(None);
    }

    conn.query_row(
        r#"
SELECT role
FROM attachment_derivations
WHERE root_sha256 = ?1 AND child_sha256 = ?2
ORDER BY CASE role
  WHEN 'root_manifest' THEN 0
  WHEN 'proxy_segment' THEN 1
  WHEN 'extracted_audio' THEN 2
  WHEN 'poster' THEN 3
  WHEN 'keyframe' THEN 4
  ELSE 99
END ASC,
created_at_ms ASC
LIMIT 1
"#,
        params![root_sha256, child_sha256],
        |row| row.get(0),
    )
    .optional()
    .map_err(Into::into)
}

pub fn delete_attachment_derivations_by_root(conn: &Connection, root_sha256: &str) -> Result<u64> {
    let root_sha256 = root_sha256.trim();
    if root_sha256.is_empty() {
        return Ok(0);
    }
    let deleted = conn.execute(
        r#"DELETE FROM attachment_derivations WHERE root_sha256 = ?1"#,
        params![root_sha256],
    )?;
    Ok(deleted as u64)
}

pub fn delete_attachment_derivations_by_child(
    conn: &Connection,
    child_sha256: &str,
) -> Result<u64> {
    let child_sha256 = child_sha256.trim();
    if child_sha256.is_empty() {
        return Ok(0);
    }
    let deleted = conn.execute(
        r#"DELETE FROM attachment_derivations WHERE child_sha256 = ?1"#,
        params![child_sha256],
    )?;
    Ok(deleted as u64)
}

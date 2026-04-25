#[derive(Clone, Debug)]
pub struct ExternalImportScanSummary {
    pub detected_source_kind: String,
    pub source_label: String,
    pub notes_count: i64,
    pub attachments_count: i64,
    pub estimated_disk_usage_bytes: i64,
    pub warnings: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct ExternalImportBatchSummary {
    pub batch_id: String,
    pub source_kind: String,
    pub source_label: String,
    pub status: String,
    pub notes_count: i64,
    pub attachments_count: i64,
    pub failed_count: i64,
    pub copied_bytes: i64,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub completed_at_ms: Option<i64>,
    pub last_error: Option<String>,
}

#[derive(Clone, Debug)]
pub struct ExternalImportProgress {
    pub batch_id: String,
    pub stage: String,
    pub done: i64,
    pub total: i64,
    pub failed_count: i64,
    pub status: String,
}

#[derive(Clone, Debug)]
pub struct SimilarExternalDocumentChunk {
    pub batch_id: String,
    pub doc_id: String,
    pub title: String,
    pub chunk_index: i64,
    pub distance: f64,
    pub snippet: String,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug, Serialize)]
struct ExternalImportDiagnosticRecord {
    stage: String,
    severity: String,
    code: String,
    message: String,
    source_rel_path: Option<String>,
    created_at_ms: i64,
}

fn external_readonly_root_dir(app_dir: &Path) -> PathBuf {
    app_dir.join("external_readonly")
}

fn external_readonly_db_path(app_dir: &Path) -> PathBuf {
    external_readonly_root_dir(app_dir).join("external_readonly.sqlite3")
}

fn external_readonly_storage_dir(app_dir: &Path) -> PathBuf {
    external_readonly_root_dir(app_dir).join("storage")
}

fn external_readonly_attachment_dir(app_dir: &Path) -> PathBuf {
    external_readonly_storage_dir(app_dir).join("attachments")
}

fn external_readonly_staging_dir(app_dir: &Path) -> PathBuf {
    external_readonly_root_dir(app_dir).join("staging")
}

const EXTERNAL_READONLY_USER_DATA_TABLES: &[&str] = &[
    "external_import_batches",
    "external_documents",
    "external_document_chunks",
    "external_attachments",
    "external_document_attachments",
    "external_phase_b_attachments",
    "external_phase_b_chunk_refs",
    "external_import_diagnostics",
];

fn external_readonly_dir_has_entries(path: &Path) -> Result<bool> {
    match fs::read_dir(path) {
        Ok(mut entries) => Ok(entries.next().is_some()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(e.into()),
    }
}

fn external_readonly_table_has_rows(conn: &Connection, table: &str) -> Result<bool> {
    let table_exists: bool = conn.query_row(
        r#"SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1)"#,
        params![table],
        |row| row.get(0),
    )?;
    if !table_exists {
        return Ok(false);
    }

    let quoted_table = table.replace('"', "\"\"");
    let sql = format!(r#"SELECT EXISTS(SELECT 1 FROM "{quoted_table}" LIMIT 1)"#);
    let has_rows: bool = conn.query_row(&sql, [], |row| row.get(0))?;
    Ok(has_rows)
}

pub(crate) fn external_readonly_has_user_data(app_dir: &Path) -> Result<bool> {
    if external_readonly_dir_has_entries(&external_readonly_storage_dir(app_dir))? {
        return Ok(true);
    }

    let db_path = external_readonly_db_path(app_dir);
    if !db_path.exists() {
        return Ok(false);
    }

    let conn = Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    for table in EXTERNAL_READONLY_USER_DATA_TABLES {
        if external_readonly_table_has_rows(&conn, table)? {
            return Ok(true);
        }
    }
    Ok(false)
}

pub(crate) fn remove_external_readonly_data(app_dir: &Path) -> Result<()> {
    best_effort_remove_dir_all(&external_readonly_root_dir(app_dir))
}

fn external_cancel_flag_path(app_dir: &Path, batch_id: &str) -> PathBuf {
    external_readonly_root_dir(app_dir).join(format!("cancel-{batch_id}.flag"))
}

fn external_attachment_aad(sha256: &str) -> Vec<u8> {
    format!("external_attachment.bytes:{sha256}").into_bytes()
}

fn external_document_title_aad(doc_id: &str) -> Vec<u8> {
    format!("external_document.title:{doc_id}").into_bytes()
}

fn external_document_body_aad(doc_id: &str) -> Vec<u8> {
    format!("external_document.body:{doc_id}").into_bytes()
}

fn external_document_tags_aad(doc_id: &str) -> Vec<u8> {
    format!("external_document.tags:{doc_id}").into_bytes()
}

fn external_chunk_aad(doc_id: &str, chunk_index: i64) -> Vec<u8> {
    format!("external_chunk.text:{doc_id}:{chunk_index}").into_bytes()
}

pub fn open_external_readonly_db(app_dir: &Path) -> Result<Connection> {
    crate::platform::sqlite_runtime::ensure_sqlite_parent_dir(
        &external_readonly_root_dir(app_dir),
    )?;
    vector::register_sqlite_vec()?;
    let conn = Connection::open(external_readonly_db_path(app_dir))?;
    apply_sqlite_open_pragmas(&conn)?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    migrate_external_readonly_db(&conn)?;
    Ok(conn)
}

fn migrate_external_readonly_db(conn: &Connection) -> Result<()> {
    let version: i64 = conn.pragma_query_value(None, "user_version", |row| row.get(0))?;
    if version < 1 {
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS external_import_batches (
  batch_id TEXT PRIMARY KEY,
  source_kind TEXT NOT NULL,
  source_label TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  completed_at_ms INTEGER,
  stats_json TEXT NOT NULL DEFAULT '{}',
  last_error TEXT
);
CREATE INDEX IF NOT EXISTS idx_external_import_batches_updated_at_ms
  ON external_import_batches(updated_at_ms DESC);

CREATE TABLE IF NOT EXISTS external_documents (
  doc_id TEXT PRIMARY KEY,
  batch_id TEXT NOT NULL,
  external_origin_id TEXT,
  source_rel_path TEXT,
  title BLOB NOT NULL,
  body_markdown BLOB NOT NULL,
  tags_json BLOB NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  checksum_sha256 TEXT NOT NULL,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(batch_id) REFERENCES external_import_batches(batch_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_external_documents_batch_id
  ON external_documents(batch_id);
CREATE INDEX IF NOT EXISTS idx_external_documents_updated_at_ms
  ON external_documents(updated_at_ms DESC);

CREATE TABLE IF NOT EXISTS external_document_chunks (
  doc_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  chunk_text BLOB NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(doc_id, chunk_index),
  FOREIGN KEY(doc_id) REFERENCES external_documents(doc_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_external_document_chunks_doc_id
  ON external_document_chunks(doc_id, chunk_index);

CREATE TABLE IF NOT EXISTS external_attachments (
  sha256 TEXT PRIMARY KEY,
  stored_path TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  mime_type TEXT NOT NULL,
  ref_count INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS external_document_attachments (
  doc_id TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  attachment_name TEXT NOT NULL,
  ordinal INTEGER NOT NULL,
  PRIMARY KEY(doc_id, sha256, ordinal),
  FOREIGN KEY(doc_id) REFERENCES external_documents(doc_id) ON DELETE CASCADE,
  FOREIGN KEY(sha256) REFERENCES external_attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_external_document_attachments_sha
  ON external_document_attachments(sha256);

CREATE TABLE IF NOT EXISTS embedding_spaces (
  space_id TEXT PRIMARY KEY,
  model_name TEXT NOT NULL,
  dim INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_external_embedding_spaces_updated_at_ms
  ON embedding_spaces(updated_at_ms DESC);

PRAGMA user_version = 1;
"#,
        )?;
    }

    if version < 2 {
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS external_phase_b_attachments (
  batch_id TEXT NOT NULL,
  doc_id TEXT NOT NULL,
  attachment_sha256 TEXT NOT NULL,
  attachment_name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  status TEXT NOT NULL,
  generated_chunk_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  completed_at_ms INTEGER,
  PRIMARY KEY(doc_id, attachment_sha256),
  FOREIGN KEY(batch_id) REFERENCES external_import_batches(batch_id) ON DELETE CASCADE,
  FOREIGN KEY(doc_id) REFERENCES external_documents(doc_id) ON DELETE CASCADE,
  FOREIGN KEY(attachment_sha256) REFERENCES external_attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_external_phase_b_attachments_batch_status
  ON external_phase_b_attachments(batch_id, status, updated_at_ms DESC);

CREATE TABLE IF NOT EXISTS external_phase_b_chunk_refs (
  doc_id TEXT NOT NULL,
  attachment_sha256 TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY(doc_id, attachment_sha256, chunk_index),
  FOREIGN KEY(doc_id) REFERENCES external_documents(doc_id) ON DELETE CASCADE,
  FOREIGN KEY(attachment_sha256) REFERENCES external_attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_external_phase_b_chunk_refs_doc_id
  ON external_phase_b_chunk_refs(doc_id, chunk_index);

PRAGMA user_version = 2;
"#,
        )?;
    }

    if version < 3 {
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS external_import_diagnostics (
  diag_id INTEGER PRIMARY KEY AUTOINCREMENT,
  batch_id TEXT NOT NULL,
  stage TEXT NOT NULL,
  severity TEXT NOT NULL,
  code TEXT NOT NULL,
  message TEXT NOT NULL,
  source_rel_path TEXT,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(batch_id) REFERENCES external_import_batches(batch_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_external_import_diagnostics_batch_created
  ON external_import_diagnostics(batch_id, created_at_ms ASC, diag_id ASC);

PRAGMA user_version = 3;
"#,
        )?;
    }

    Ok(())
}

fn upsert_external_embedding_space(conn: &Connection, model_name: &str, dim: usize) -> Result<String> {
    let space_id = embedding_space_id(model_name, dim)?;
    let now = now_ms();
    conn.execute(
        r#"INSERT INTO embedding_spaces(space_id, model_name, dim, created_at_ms, updated_at_ms)
           VALUES (?1, ?2, ?3, ?4, ?4)
           ON CONFLICT(space_id) DO UPDATE SET
             model_name = excluded.model_name,
             dim = excluded.dim,
             updated_at_ms = excluded.updated_at_ms"#,
        params![space_id, model_name, dim as i64, now],
    )?;
    Ok(space_id)
}

fn external_chunk_embeddings_table(space_id: &str) -> Result<String> {
    if !is_safe_sqlite_ident(space_id) {
        return Err(anyhow!("invalid embedding space id: {space_id}"));
    }
    Ok(format!("external_chunk_embeddings_{space_id}"))
}

fn ensure_external_chunk_vec_table_for_space(
    conn: &Connection,
    space_id: &str,
    dim: usize,
) -> Result<String> {
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("invalid embedding dim: {dim}"));
    }
    let table = external_chunk_embeddings_table(space_id)?;
    if !sqlite_table_exists(conn, &table)? {
        conn.execute_batch(&if crate::vector::is_available() {
            format!(
                r#"
CREATE VIRTUAL TABLE "{table}" USING vec0(
  embedding float[{dim}],
  chunk_rowid INTEGER,
  doc_id TEXT,
  chunk_index INTEGER,
  model_name TEXT
);
"#
            )
        } else {
            format!(
                r#"
CREATE TABLE "{table}"(
  embedding BLOB,
  chunk_rowid INTEGER,
  doc_id TEXT,
  chunk_index INTEGER,
  model_name TEXT
);
"#
            )
        })?;
    }

    if !crate::vector::is_available() {
        return Ok(table);
    }

    let actual_dim = vec0_dim_from_sqlite_master(conn, &table)?.unwrap_or(0);
    if actual_dim != dim {
        return Err(anyhow!(
            "external chunk vec0 dim mismatch: expected {dim}, got {actual_dim} (table={table})"
        ));
    }
    Ok(table)
}

fn list_external_embedding_space_ids(conn: &Connection) -> Result<Vec<String>> {
    if !sqlite_table_exists(conn, "embedding_spaces")? {
        return Ok(Vec::new());
    }

    let mut stmt = conn.prepare(
        r#"SELECT space_id FROM embedding_spaces ORDER BY updated_at_ms DESC, space_id ASC"#,
    )?;
    let mut rows = stmt.query([])?;
    let mut out = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        out.push(row.get(0)?);
    }
    Ok(out)
}

fn encode_external_document_title(key: &[u8; 32], doc_id: &str, title: &str) -> Result<Vec<u8>> {
    encrypt_bytes(key, title.as_bytes(), &external_document_title_aad(doc_id))
}

fn decode_external_document_title(key: &[u8; 32], doc_id: &str, blob: &[u8]) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &external_document_title_aad(doc_id))?;
    String::from_utf8(bytes).map_err(|_| anyhow!("external document title is not valid utf-8"))
}

fn encode_external_document_body(key: &[u8; 32], doc_id: &str, body: &str) -> Result<Vec<u8>> {
    encrypt_bytes(key, body.as_bytes(), &external_document_body_aad(doc_id))
}

fn encode_external_document_tags(key: &[u8; 32], doc_id: &str, tags_json: &str) -> Result<Vec<u8>> {
    encrypt_bytes(key, tags_json.as_bytes(), &external_document_tags_aad(doc_id))
}

fn encode_external_chunk_text(key: &[u8; 32], doc_id: &str, chunk_index: i64, text: &str) -> Result<Vec<u8>> {
    encrypt_bytes(key, text.as_bytes(), &external_chunk_aad(doc_id, chunk_index))
}

fn decode_external_chunk_text(
    key: &[u8; 32],
    doc_id: &str,
    chunk_index: i64,
    blob: &[u8],
) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &external_chunk_aad(doc_id, chunk_index))?;
    String::from_utf8(bytes).map_err(|_| anyhow!("external chunk text is not valid utf-8"))
}

fn parse_external_stats_json(
    stats_json: &str,
) -> (i64, i64, i64, i64) {
    let value: serde_json::Value = serde_json::from_str(stats_json).unwrap_or(serde_json::json!({}));
    let notes_count = value.get("notes_count").and_then(|v| v.as_i64()).unwrap_or(0);
    let attachments_count = value
        .get("attachments_count")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let failed_count = value.get("failed_count").and_then(|v| v.as_i64()).unwrap_or(0);
    let copied_bytes = value.get("copied_bytes").and_then(|v| v.as_i64()).unwrap_or(0);
    (notes_count, attachments_count, failed_count, copied_bytes)
}

fn build_external_stats_json(
    notes_count: i64,
    attachments_count: i64,
    failed_count: i64,
    copied_bytes: i64,
) -> String {
    serde_json::json!({
        "notes_count": notes_count,
        "attachments_count": attachments_count,
        "failed_count": failed_count,
        "copied_bytes": copied_bytes,
    })
    .to_string()
}

fn read_external_import_batch_summary(conn: &Connection, batch_id: &str) -> Result<ExternalImportBatchSummary> {
    conn.query_row(
        r#"SELECT batch_id, source_kind, source_label, status, created_at_ms, updated_at_ms,
                  completed_at_ms, stats_json, last_error
           FROM external_import_batches
           WHERE batch_id = ?1"#,
        params![batch_id],
        |row| {
            let stats_json: String = row.get(7)?;
            let (notes_count, attachments_count, failed_count, copied_bytes) =
                parse_external_stats_json(&stats_json);
            Ok(ExternalImportBatchSummary {
                batch_id: row.get(0)?,
                source_kind: row.get(1)?,
                source_label: row.get(2)?,
                status: row.get(3)?,
                notes_count,
                attachments_count,
                failed_count,
                copied_bytes,
                created_at_ms: row.get(4)?,
                updated_at_ms: row.get(5)?,
                completed_at_ms: row.get(6)?,
                last_error: row.get(8)?,
            })
        },
    )
    .map_err(Into::into)
}

fn insert_external_import_diagnostic(
    conn: &Connection,
    batch_id: &str,
    stage: &str,
    severity: &str,
    code: &str,
    message: &str,
    source_rel_path: Option<&str>,
) -> Result<()> {
    conn.execute(
        r#"INSERT INTO external_import_diagnostics(
             batch_id, stage, severity, code, message, source_rel_path, created_at_ms
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"#,
        params![
            batch_id,
            stage,
            severity,
            code,
            message,
            source_rel_path,
            now_ms(),
        ],
    )?;
    Ok(())
}

fn list_external_import_diagnostics(
    conn: &Connection,
    batch_id: &str,
) -> Result<Vec<ExternalImportDiagnosticRecord>> {
    let mut stmt = conn.prepare(
        r#"SELECT stage, severity, code, message, source_rel_path, created_at_ms
           FROM external_import_diagnostics
           WHERE batch_id = ?1
           ORDER BY created_at_ms ASC, diag_id ASC"#,
    )?;
    let mut rows = stmt.query(params![batch_id])?;
    let mut out = Vec::<ExternalImportDiagnosticRecord>::new();
    while let Some(row) = rows.next()? {
        out.push(ExternalImportDiagnosticRecord {
            stage: row.get(0)?,
            severity: row.get(1)?,
            code: row.get(2)?,
            message: row.get(3)?,
            source_rel_path: row.get(4)?,
            created_at_ms: row.get(5)?,
        });
    }
    Ok(out)
}

fn build_external_import_batch_report_value(
    conn: &Connection,
    batch_id: &str,
) -> Result<serde_json::Value> {
    let summary = read_external_import_batch_summary(conn, batch_id)?;
    let success_count: i64 = conn.query_row(
        r#"SELECT COUNT(*) FROM external_documents WHERE batch_id = ?1"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    let copied_attachment_count: i64 = conn.query_row(
        r#"SELECT COUNT(DISTINCT a.sha256)
           FROM external_document_attachments a
           JOIN external_documents d ON d.doc_id = a.doc_id
           WHERE d.batch_id = ?1"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    let elapsed_ms = (summary.completed_at_ms.unwrap_or(summary.updated_at_ms) - summary.created_at_ms)
        .max(0);
    let diagnostics = list_external_import_diagnostics(conn, batch_id)?;
    Ok(serde_json::json!({
        "batch_id": summary.batch_id,
        "source_kind": summary.source_kind,
        "source_label": summary.source_label,
        "status": summary.status,
        "notes_count": summary.notes_count,
        "attachments_count": summary.attachments_count,
        "failed_count": summary.failed_count,
        "copied_bytes": summary.copied_bytes,
        "success_count": success_count,
        "copied_attachment_count": copied_attachment_count,
        "disk_usage_bytes": summary.copied_bytes,
        "elapsed_ms": elapsed_ms,
        "created_at_ms": summary.created_at_ms,
        "updated_at_ms": summary.updated_at_ms,
        "completed_at_ms": summary.completed_at_ms,
        "last_error": summary.last_error,
        "diagnostics": diagnostics,
    }))
}

pub fn read_external_import_batch_report_json(app_dir: &Path, batch_id: &str) -> Result<String> {
    let conn = open_external_readonly_db(app_dir)?;
    Ok(build_external_import_batch_report_value(&conn, batch_id)?.to_string())
}

pub fn list_external_import_batches(app_dir: &Path) -> Result<Vec<ExternalImportBatchSummary>> {
    let conn = open_external_readonly_db(app_dir)?;
    let mut stmt = conn.prepare(
        r#"SELECT batch_id
           FROM external_import_batches
           ORDER BY created_at_ms DESC, batch_id DESC"#,
    )?;
    let mut rows = stmt.query([])?;
    let mut out = Vec::<ExternalImportBatchSummary>::new();
    while let Some(row) = rows.next()? {
        let batch_id: String = row.get(0)?;
        out.push(read_external_import_batch_summary(&conn, &batch_id)?);
    }
    Ok(out)
}

fn best_effort_remove_external_path(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}

fn infer_external_mime_type(path: &Path) -> String {
    let ext = path
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| value.trim().to_ascii_lowercase())
        .unwrap_or_default();
    match ext.as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "pdf" => "application/pdf",
        "md" => "text/markdown",
        "txt" => "text/plain",
        "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "mp3" => "audio/mpeg",
        "wav" => "audio/wav",
        "m4a" => "audio/mp4",
        "mp4" => "video/mp4",
        _ => "application/octet-stream",
    }
    .to_string()
}

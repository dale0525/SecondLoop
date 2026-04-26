use std::fs;
use std::path::{Component, Path};

use crate::crypto::{decrypt_bytes, is_ciphertext_too_short_error, is_decrypt_failed_error};
use anyhow::Result;
use rusqlite::{params, Connection, OpenFlags};

const MIN_ENCRYPTED_BLOB_LEN: usize = 24 + 16;
const MAX_PROBE_DB_BLOB_BYTES: u64 = 16 * 1024 * 1024;
const MAX_TOTAL_PROBE_DB_BLOB_BYTES: u64 = 64 * 1024 * 1024;
const MAX_PROBE_FILE_BYTES: u64 = 64 * 1024 * 1024;
const MAX_TOTAL_PROBE_FILE_BYTES: u64 = 256 * 1024 * 1024;

const FIXED_AAD_PROBES: &[FixedAadProbe] = &[
    FixedAadProbe {
        table: "conversations",
        column: "title",
        aad: b"conversation.title",
    },
    FixedAadProbe {
        table: "messages",
        column: "content",
        aad: b"message.content",
    },
    FixedAadProbe {
        table: "todos",
        column: "title",
        aad: b"todo.title",
    },
    FixedAadProbe {
        table: "events",
        column: "title",
        aad: b"event.title",
    },
];

const ROW_AAD_PROBES: &[RowAadProbe] = &[
    RowAadProbe {
        table: "tags",
        column: "name",
        id_column: "id",
        aad_prefix: "tag.name:",
    },
    RowAadProbe {
        table: "attachment_metadata",
        column: "title",
        id_column: "attachment_sha256",
        aad_prefix: "attachment.metadata.title:",
    },
    RowAadProbe {
        table: "attachment_metadata",
        column: "filenames",
        id_column: "attachment_sha256",
        aad_prefix: "attachment.metadata.filenames:",
    },
    RowAadProbe {
        table: "attachment_metadata",
        column: "source_urls",
        id_column: "attachment_sha256",
        aad_prefix: "attachment.metadata.source_urls:",
    },
    RowAadProbe {
        table: "attachment_exif",
        column: "metadata",
        id_column: "attachment_sha256",
        aad_prefix: "attachment.exif:",
    },
    RowAadProbe {
        table: "todo_checklist_items",
        column: "content",
        id_column: "id",
        aad_prefix: "todo_checklist_item.content:",
    },
    RowAadProbe {
        table: "todo_checklist_suggestions",
        column: "content",
        id_column: "id",
        aad_prefix: "todo_checklist_suggestion.content:",
    },
    RowAadProbe {
        table: "todo_followup_suggestions",
        column: "content",
        id_column: "id",
        aad_prefix: "todo_followup_suggestion.content:",
    },
    RowAadProbe {
        table: "todo_activities",
        column: "content",
        id_column: "id",
        aad_prefix: "todo_activity.content:",
    },
    RowAadProbe {
        table: "semantic_parse_jobs",
        column: "applied_todo_title",
        id_column: "message_id",
        aad_prefix: "semantic_parse_job.title:",
    },
    RowAadProbe {
        table: "semantic_parse_jobs",
        column: "suggested_tags_json",
        id_column: "message_id",
        aad_prefix: "semantic_parse_job.suggested_tags:",
    },
    RowAadProbe {
        table: "semantic_parse_jobs",
        column: "applied_tag_ids_json",
        id_column: "message_id",
        aad_prefix: "semantic_parse_job.applied_tag_ids:",
    },
    RowAadProbe {
        table: "oplog",
        column: "op_json",
        id_column: "op_id",
        aad_prefix: "oplog.op_json:",
    },
];

const EXTERNAL_ROW_AAD_PROBES: &[RowAadProbe] = &[
    RowAadProbe {
        table: "external_documents",
        column: "title",
        id_column: "doc_id",
        aad_prefix: "external_document.title:",
    },
    RowAadProbe {
        table: "external_documents",
        column: "body_markdown",
        id_column: "doc_id",
        aad_prefix: "external_document.body:",
    },
    RowAadProbe {
        table: "external_documents",
        column: "tags_json",
        id_column: "doc_id",
        aad_prefix: "external_document.tags:",
    },
];

pub(super) enum MissingAuthKeyProbe {
    NoEncryptedData,
    ValidKey,
    UnableToValidate,
}

struct FixedAadProbe {
    table: &'static str,
    column: &'static str,
    aad: &'static [u8],
}

struct RowAadProbe {
    table: &'static str,
    column: &'static str,
    id_column: &'static str,
    aad_prefix: &'static str,
}

#[derive(Clone, Copy)]
enum ProbeMatch {
    NoEncryptedData,
    ValidKey,
    UnableToValidate,
}

#[derive(Default)]
struct ProbeAccumulator {
    found_valid: bool,
    found_unverifiable: bool,
}

impl ProbeAccumulator {
    fn add(&mut self, result: ProbeMatch) -> Option<ProbeMatch> {
        match result {
            ProbeMatch::NoEncryptedData => None,
            ProbeMatch::ValidKey => {
                self.found_valid = true;
                None
            }
            ProbeMatch::UnableToValidate => {
                self.found_unverifiable = true;
                Some(ProbeMatch::UnableToValidate)
            }
        }
    }

    fn finish(self) -> ProbeMatch {
        if self.found_unverifiable {
            ProbeMatch::UnableToValidate
        } else if self.found_valid {
            ProbeMatch::ValidKey
        } else {
            ProbeMatch::NoEncryptedData
        }
    }
}

pub(super) fn missing_auth_key_probe(
    app_dir: &Path,
    key: &[u8; 32],
) -> Result<MissingAuthKeyProbe> {
    let mut accumulator = ProbeAccumulator::default();

    if let Some(result) = probe_db_path(&app_dir.join("secondloop.sqlite3"), key, |conn, key| {
        probe_main_db(app_dir, conn, key)
    })? {
        if let Some(result) = accumulator.add(result) {
            return Ok(missing_auth_key_probe_result(result));
        }
    }

    let external_db_path = app_dir
        .join("external_readonly")
        .join("external_readonly.sqlite3");
    if let Some(result) = probe_db_path(&external_db_path, key, |conn, key| {
        probe_external_readonly_db(app_dir, conn, key)
    })? {
        if let Some(result) = accumulator.add(result) {
            return Ok(missing_auth_key_probe_result(result));
        }
    }

    Ok(missing_auth_key_probe_result(accumulator.finish()))
}

fn missing_auth_key_probe_result(result: ProbeMatch) -> MissingAuthKeyProbe {
    match result {
        ProbeMatch::NoEncryptedData => MissingAuthKeyProbe::NoEncryptedData,
        ProbeMatch::ValidKey => MissingAuthKeyProbe::ValidKey,
        ProbeMatch::UnableToValidate => MissingAuthKeyProbe::UnableToValidate,
    }
}

fn probe_db_path<F>(db_path: &Path, key: &[u8; 32], probe: F) -> Result<Option<ProbeMatch>>
where
    F: FnOnce(&Connection, &[u8; 32]) -> Result<ProbeMatch>,
{
    if !db_path.exists() {
        return Ok(None);
    }
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    probe(&conn, key).map(Some)
}

fn probe_main_db(app_dir: &Path, conn: &Connection, key: &[u8; 32]) -> Result<ProbeMatch> {
    let mut accumulator = ProbeAccumulator::default();
    for probe in FIXED_AAD_PROBES {
        if let Some(result) = accumulator.add(fixed_aad_probe_matches_key(conn, key, probe)?) {
            return Ok(result);
        }
    }
    for probe in ROW_AAD_PROBES {
        if let Some(result) = accumulator.add(row_aad_probe_matches_key(conn, key, probe)?) {
            return Ok(result);
        }
    }
    for result in [
        attachment_place_probe_matches_key(conn, key)?,
        attachment_annotation_probe_matches_key(conn, key)?,
        attachment_file_probe_matches_key(app_dir, conn, key)?,
        attachment_variant_file_probe_matches_key(app_dir, conn, key)?,
    ] {
        if let Some(result) = accumulator.add(result) {
            return Ok(result);
        }
    }
    Ok(accumulator.finish())
}

fn probe_external_readonly_db(
    app_dir: &Path,
    conn: &Connection,
    key: &[u8; 32],
) -> Result<ProbeMatch> {
    let mut accumulator = ProbeAccumulator::default();
    for probe in EXTERNAL_ROW_AAD_PROBES {
        if let Some(result) = accumulator.add(row_aad_probe_matches_key(conn, key, probe)?) {
            return Ok(result);
        }
    }
    for result in [
        external_chunk_probe_matches_key(conn, key)?,
        external_attachment_file_probe_matches_key(app_dir, conn, key)?,
    ] {
        if let Some(result) = accumulator.add(result) {
            return Ok(result);
        }
    }
    Ok(accumulator.finish())
}

fn fixed_aad_probe_matches_key(
    conn: &Connection,
    key: &[u8; 32],
    probe: &FixedAadProbe,
) -> Result<ProbeMatch> {
    encrypted_probe_matches_key(conn, key, probe.table, probe.column, |_| {
        Ok(probe.aad.to_vec())
    })
}

fn row_aad_probe_matches_key(
    conn: &Connection,
    key: &[u8; 32],
    probe: &RowAadProbe,
) -> Result<ProbeMatch> {
    encrypted_probe_matches_key(conn, key, probe.table, probe.column, |row| {
        let id: String = row.get(0)?;
        Ok(format!("{}{}", probe.aad_prefix, id).into_bytes())
    })
}

fn external_chunk_probe_matches_key(conn: &Connection, key: &[u8; 32]) -> Result<ProbeMatch> {
    encrypted_probe_matches_key_with_ids(
        conn,
        key,
        "external_document_chunks",
        "chunk_text",
        &["doc_id", "chunk_index"],
        |row| {
            let doc_id: String = row.get(0)?;
            let chunk_index: i64 = row.get(1)?;
            Ok(format!("external_chunk.text:{doc_id}:{chunk_index}").into_bytes())
        },
    )
}

fn attachment_place_probe_matches_key(conn: &Connection, key: &[u8; 32]) -> Result<ProbeMatch> {
    encrypted_probe_matches_key_with_ids(
        conn,
        key,
        "attachment_places",
        "payload",
        &["attachment_sha256", "lang"],
        |row| {
            let attachment_sha256: String = row.get(0)?;
            let lang: String = row.get(1)?;
            Ok(format!("attachment.place:{attachment_sha256}:{lang}").into_bytes())
        },
    )
}

fn attachment_annotation_probe_matches_key(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<ProbeMatch> {
    encrypted_probe_matches_key_with_ids(
        conn,
        key,
        "attachment_annotations",
        "payload",
        &["attachment_sha256", "lang"],
        |row| {
            let attachment_sha256: String = row.get(0)?;
            let lang: String = row.get(1)?;
            Ok(format!("attachment.annotation:{attachment_sha256}:{lang}").into_bytes())
        },
    )
}

fn attachment_file_probe_matches_key(
    app_dir: &Path,
    conn: &Connection,
    key: &[u8; 32],
) -> Result<ProbeMatch> {
    encrypted_file_probe_matches_key(
        app_dir,
        conn,
        key,
        "attachments",
        &["sha256", "path"],
        |row| {
            let sha256: String = row.get(0)?;
            let stored_path: String = row.get(1)?;
            Ok((
                stored_path,
                format!("attachment.bytes:{sha256}").into_bytes(),
            ))
        },
    )
}

fn attachment_variant_file_probe_matches_key(
    app_dir: &Path,
    conn: &Connection,
    key: &[u8; 32],
) -> Result<ProbeMatch> {
    encrypted_file_probe_matches_key(
        app_dir,
        conn,
        key,
        "attachment_variants",
        &["attachment_sha256", "variant", "path"],
        |row| {
            let attachment_sha256: String = row.get(0)?;
            let variant: String = row.get(1)?;
            let stored_path: String = row.get(2)?;
            Ok((
                stored_path,
                format!("attachment.variant.bytes:{attachment_sha256}:{variant}").into_bytes(),
            ))
        },
    )
}

fn external_attachment_file_probe_matches_key(
    app_dir: &Path,
    conn: &Connection,
    key: &[u8; 32],
) -> Result<ProbeMatch> {
    encrypted_file_probe_matches_key(
        app_dir,
        conn,
        key,
        "external_attachments",
        &["sha256", "stored_path"],
        |row| {
            let sha256: String = row.get(0)?;
            let stored_path: String = row.get(1)?;
            Ok((
                stored_path,
                format!("external_attachment.bytes:{sha256}").into_bytes(),
            ))
        },
    )
}

fn encrypted_probe_matches_key<F>(
    conn: &Connection,
    key: &[u8; 32],
    table: &str,
    column: &str,
    aad_for_row: F,
) -> Result<ProbeMatch>
where
    F: Fn(&rusqlite::Row<'_>) -> Result<Vec<u8>>,
{
    let id_columns = vec![id_column_for_probe(table, column).unwrap_or("rowid")];
    encrypted_probe_matches_key_with_ids(conn, key, table, column, &id_columns, aad_for_row)
}

fn encrypted_probe_matches_key_with_ids<F>(
    conn: &Connection,
    key: &[u8; 32],
    table: &str,
    column: &str,
    id_columns: &[&str],
    aad_for_row: F,
) -> Result<ProbeMatch>
where
    F: Fn(&rusqlite::Row<'_>) -> Result<Vec<u8>>,
{
    if !super::table_has_rows(conn, table)?
        || !probe_columns_exist(conn, table, column, id_columns)?
    {
        return Ok(ProbeMatch::NoEncryptedData);
    }

    let quoted_table = quote_ident(table);
    let quoted_column = quote_ident(column);
    let select_ids = id_columns
        .iter()
        .map(|id_column| {
            if *id_column == "rowid" {
                "rowid".to_string()
            } else {
                quote_ident(id_column)
            }
        })
        .collect::<Vec<_>>()
        .join(", ");
    let sql = format!(
        r#"
SELECT {select_ids}, length({quoted_column}), {quoted_column}
FROM {quoted_table}
WHERE typeof({quoted_column}) = 'blob'
  AND length({quoted_column}) >= ?1
ORDER BY rowid
"#
    );
    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query(params![MIN_ENCRYPTED_BLOB_LEN as i64])?;
    let len_index = id_columns.len();
    let blob_index = id_columns.len() + 1;
    let mut accumulator = ProbeAccumulator::default();
    let mut total_blob_bytes = 0u64;
    while let Some(row) = rows.next()? {
        let blob_len = nonnegative_i64_to_u64(row.get(len_index)?);
        if blob_len > MAX_PROBE_DB_BLOB_BYTES
            || total_blob_bytes.saturating_add(blob_len) > MAX_TOTAL_PROBE_DB_BLOB_BYTES
        {
            return Ok(ProbeMatch::UnableToValidate);
        }
        let blob: Vec<u8> = row.get(blob_index)?;
        let bytes_len = blob.len() as u64;
        if bytes_len > MAX_PROBE_DB_BLOB_BYTES
            || total_blob_bytes.saturating_add(bytes_len) > MAX_TOTAL_PROBE_DB_BLOB_BYTES
        {
            return Ok(ProbeMatch::UnableToValidate);
        }
        total_blob_bytes += bytes_len;
        let aad = aad_for_row(row)?;
        if let Some(result) = accumulator.add(match probe_blob_matches_key(key, &blob, &aad)? {
            Some(true) => ProbeMatch::ValidKey,
            Some(false) => ProbeMatch::UnableToValidate,
            None => ProbeMatch::NoEncryptedData,
        }) {
            return Ok(result);
        }
    }
    Ok(accumulator.finish())
}

fn encrypted_file_probe_matches_key<F>(
    app_dir: &Path,
    conn: &Connection,
    key: &[u8; 32],
    table: &str,
    columns: &[&str],
    aad_and_path_for_row: F,
) -> Result<ProbeMatch>
where
    F: Fn(&rusqlite::Row<'_>) -> Result<(String, Vec<u8>)>,
{
    let Some((&path_column, id_columns)) = columns.split_last() else {
        return Ok(ProbeMatch::NoEncryptedData);
    };
    if !super::table_has_rows(conn, table)?
        || !probe_columns_exist(conn, table, path_column, id_columns)?
    {
        return Ok(ProbeMatch::NoEncryptedData);
    }

    let quoted_table = quote_ident(table);
    let select_columns = columns
        .iter()
        .map(|column| quote_ident(column))
        .collect::<Vec<_>>()
        .join(", ");
    let sql = format!(
        r#"
SELECT {select_columns}
FROM {quoted_table}
ORDER BY rowid
"#
    );
    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query([])?;
    let mut accumulator = ProbeAccumulator::default();
    let mut total_file_bytes = 0u64;
    while let Some(row) = rows.next()? {
        let (stored_path, aad) = aad_and_path_for_row(row)?;
        let blob = match read_app_relative_file(app_dir, &stored_path, &mut total_file_bytes)? {
            ProbeFileRead::NoEncryptedData => continue,
            ProbeFileRead::Blob(blob) => blob,
            ProbeFileRead::Indeterminate => {
                return Ok(ProbeMatch::UnableToValidate);
            }
        };
        if let Some(result) = accumulator.add(match probe_blob_matches_key(key, &blob, &aad)? {
            Some(true) => ProbeMatch::ValidKey,
            Some(false) => ProbeMatch::UnableToValidate,
            None => ProbeMatch::NoEncryptedData,
        }) {
            return Ok(result);
        }
    }
    Ok(accumulator.finish())
}

fn probe_blob_matches_key(key: &[u8; 32], blob: &[u8], aad: &[u8]) -> Result<Option<bool>> {
    if blob.len() < MIN_ENCRYPTED_BLOB_LEN {
        return Ok(None);
    }
    match decrypt_bytes(key, blob, aad) {
        Ok(_) => Ok(Some(true)),
        Err(error) if is_decrypt_failed_error(&error) => Ok(Some(false)),
        Err(error) if is_ciphertext_too_short_error(&error) => Ok(None),
        Err(error) => Err(error),
    }
}

enum ProbeFileRead {
    NoEncryptedData,
    Blob(Vec<u8>),
    Indeterminate,
}

fn read_app_relative_file(
    app_dir: &Path,
    stored_path: &str,
    total_file_bytes: &mut u64,
) -> Result<ProbeFileRead> {
    let relative_path = Path::new(stored_path);
    if !is_safe_app_relative_path(relative_path) {
        return Ok(ProbeFileRead::Indeterminate);
    }
    let full_path = app_dir.join(relative_path);
    let metadata = match fs::symlink_metadata(&full_path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(ProbeFileRead::NoEncryptedData);
        }
        Err(error) => return Err(error.into()),
    };
    if metadata.file_type().is_symlink() {
        return Ok(ProbeFileRead::Indeterminate);
    }
    if !metadata.is_file() {
        return Ok(ProbeFileRead::Indeterminate);
    }
    if !canonical_path_stays_in_app_dir(app_dir, &full_path)? {
        return Ok(ProbeFileRead::Indeterminate);
    }
    let file_len = metadata.len();
    if file_len < MIN_ENCRYPTED_BLOB_LEN as u64 {
        return Ok(ProbeFileRead::NoEncryptedData);
    }
    if file_len > MAX_PROBE_FILE_BYTES
        || total_file_bytes.saturating_add(file_len) > MAX_TOTAL_PROBE_FILE_BYTES
    {
        return Ok(ProbeFileRead::Indeterminate);
    }
    let bytes = fs::read(&full_path)?;
    let bytes_len = bytes.len() as u64;
    if bytes_len > MAX_PROBE_FILE_BYTES
        || total_file_bytes.saturating_add(bytes_len) > MAX_TOTAL_PROBE_FILE_BYTES
    {
        return Ok(ProbeFileRead::Indeterminate);
    }
    *total_file_bytes += bytes_len;
    Ok(ProbeFileRead::Blob(bytes))
}

fn nonnegative_i64_to_u64(value: i64) -> u64 {
    u64::try_from(value).unwrap_or(u64::MAX)
}

fn canonical_path_stays_in_app_dir(app_dir: &Path, path: &Path) -> Result<bool> {
    let canonical_app_dir = app_dir.canonicalize()?;
    let canonical_path = path.canonicalize()?;
    Ok(canonical_path.starts_with(canonical_app_dir))
}

fn is_safe_app_relative_path(path: &Path) -> bool {
    !path.is_absolute()
        && path
            .components()
            .all(|component| matches!(component, Component::Normal(_) | Component::CurDir))
}

fn id_column_for_probe(table: &str, column: &str) -> Option<&'static str> {
    ROW_AAD_PROBES
        .iter()
        .chain(EXTERNAL_ROW_AAD_PROBES.iter())
        .find(|probe| probe.table == table && probe.column == column)
        .map(|probe| probe.id_column)
}

fn table_column_exists(conn: &Connection, table: &str, column: &str) -> Result<bool> {
    let quoted_table = quote_ident(table);
    let sql = format!("PRAGMA table_info({quoted_table})");
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(1))?;
    for row in rows {
        if row? == column {
            return Ok(true);
        }
    }
    Ok(false)
}

fn probe_columns_exist(
    conn: &Connection,
    table: &str,
    encrypted_column: &str,
    id_columns: &[&str],
) -> Result<bool> {
    if !table_column_exists(conn, table, encrypted_column)? {
        return Ok(false);
    }
    for id_column in id_columns {
        if *id_column != "rowid" && !table_column_exists(conn, table, id_column)? {
            return Ok(false);
        }
    }
    Ok(true)
}

fn quote_ident(value: &str) -> String {
    format!(r#""{}""#, value.replace('"', "\"\""))
}

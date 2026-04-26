use std::path::Path;

use crate::crypto::{decrypt_bytes, is_ciphertext_too_short_error, is_decrypt_failed_error};
use anyhow::Result;
use rusqlite::{params, Connection, OpenFlags};

const MIN_ENCRYPTED_BLOB_LEN: usize = 24 + 16;

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
    InvalidKey,
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
    InvalidKey,
}

pub(super) fn missing_auth_key_probe(
    app_dir: &Path,
    key: &[u8; 32],
) -> Result<MissingAuthKeyProbe> {
    let mut found_valid = false;

    if let Some(result) = probe_db_path(&app_dir.join("secondloop.sqlite3"), key, probe_main_db)? {
        match result {
            ProbeMatch::InvalidKey => return Ok(MissingAuthKeyProbe::InvalidKey),
            ProbeMatch::ValidKey => found_valid = true,
            ProbeMatch::NoEncryptedData => {}
        }
    }

    let external_db_path = app_dir
        .join("external_readonly")
        .join("external_readonly.sqlite3");
    if let Some(result) = probe_db_path(&external_db_path, key, probe_external_readonly_db)? {
        match result {
            ProbeMatch::InvalidKey => return Ok(MissingAuthKeyProbe::InvalidKey),
            ProbeMatch::ValidKey => found_valid = true,
            ProbeMatch::NoEncryptedData => {}
        }
    }

    Ok(if found_valid {
        MissingAuthKeyProbe::ValidKey
    } else {
        MissingAuthKeyProbe::NoEncryptedData
    })
}

fn probe_db_path(
    db_path: &Path,
    key: &[u8; 32],
    probe: fn(&Connection, &[u8; 32]) -> Result<ProbeMatch>,
) -> Result<Option<ProbeMatch>> {
    if !db_path.exists() {
        return Ok(None);
    }
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    probe(&conn, key).map(Some)
}

fn probe_main_db(conn: &Connection, key: &[u8; 32]) -> Result<ProbeMatch> {
    let mut found_valid = false;
    for probe in FIXED_AAD_PROBES {
        match fixed_aad_probe_matches_key(conn, key, probe)? {
            Some(false) => return Ok(ProbeMatch::InvalidKey),
            Some(true) => found_valid = true,
            None => {}
        }
    }
    for probe in ROW_AAD_PROBES {
        match row_aad_probe_matches_key(conn, key, probe)? {
            Some(false) => return Ok(ProbeMatch::InvalidKey),
            Some(true) => found_valid = true,
            None => {}
        }
    }
    Ok(if found_valid {
        ProbeMatch::ValidKey
    } else {
        ProbeMatch::NoEncryptedData
    })
}

fn probe_external_readonly_db(conn: &Connection, key: &[u8; 32]) -> Result<ProbeMatch> {
    let mut found_valid = false;
    for probe in EXTERNAL_ROW_AAD_PROBES {
        match row_aad_probe_matches_key(conn, key, probe)? {
            Some(false) => return Ok(ProbeMatch::InvalidKey),
            Some(true) => found_valid = true,
            None => {}
        }
    }
    match external_chunk_probe_matches_key(conn, key)? {
        Some(false) => return Ok(ProbeMatch::InvalidKey),
        Some(true) => found_valid = true,
        None => {}
    }
    Ok(if found_valid {
        ProbeMatch::ValidKey
    } else {
        ProbeMatch::NoEncryptedData
    })
}

fn fixed_aad_probe_matches_key(
    conn: &Connection,
    key: &[u8; 32],
    probe: &FixedAadProbe,
) -> Result<Option<bool>> {
    encrypted_probe_matches_key(conn, key, probe.table, probe.column, |_| {
        Ok(probe.aad.to_vec())
    })
}

fn row_aad_probe_matches_key(
    conn: &Connection,
    key: &[u8; 32],
    probe: &RowAadProbe,
) -> Result<Option<bool>> {
    encrypted_probe_matches_key(conn, key, probe.table, probe.column, |row| {
        let id: String = row.get(0)?;
        Ok(format!("{}{}", probe.aad_prefix, id).into_bytes())
    })
}

fn external_chunk_probe_matches_key(conn: &Connection, key: &[u8; 32]) -> Result<Option<bool>> {
    encrypted_probe_matches_key(conn, key, "external_document_chunks", "chunk_text", |row| {
        let doc_id: String = row.get(0)?;
        let chunk_index: i64 = row.get(1)?;
        Ok(format!("external_chunk.text:{doc_id}:{chunk_index}").into_bytes())
    })
}

fn encrypted_probe_matches_key<F>(
    conn: &Connection,
    key: &[u8; 32],
    table: &str,
    column: &str,
    aad_for_row: F,
) -> Result<Option<bool>>
where
    F: Fn(&rusqlite::Row<'_>) -> Result<Vec<u8>>,
{
    let id_columns = if table == "external_document_chunks" {
        vec!["doc_id", "chunk_index"]
    } else {
        vec![id_column_for_probe(table, column).unwrap_or("rowid")]
    };
    if !super::table_has_rows(conn, table)?
        || !probe_columns_exist(conn, table, column, &id_columns)?
    {
        return Ok(None);
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
SELECT {select_ids}, {quoted_column}
FROM {quoted_table}
WHERE typeof({quoted_column}) = 'blob'
  AND length({quoted_column}) >= ?1
ORDER BY rowid
"#
    );
    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query(params![MIN_ENCRYPTED_BLOB_LEN as i64])?;
    let blob_index = id_columns.len();
    let mut found_valid = false;
    while let Some(row) = rows.next()? {
        let blob: Vec<u8> = row.get(blob_index)?;
        let aad = aad_for_row(row)?;
        match decrypt_bytes(key, &blob, &aad) {
            Ok(_) => found_valid = true,
            Err(error) if is_decrypt_failed_error(&error) => return Ok(Some(false)),
            Err(error) if is_ciphertext_too_short_error(&error) => {}
            Err(error) => return Err(error),
        }
    }
    Ok(found_valid.then_some(true))
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

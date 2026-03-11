
fn insert_external_import_batch(
    conn: &Connection,
    batch_id: &str,
    source_kind: &str,
    source_label: &str,
) -> Result<()> {
    let now = now_ms();
    conn.execute(
        r#"INSERT INTO external_import_batches(
             batch_id, source_kind, source_label, status, created_at_ms, updated_at_ms, completed_at_ms, stats_json, last_error
           ) VALUES (?1, ?2, ?3, 'in_progress', ?4, ?4, NULL, '{}', NULL)"#,
        params![batch_id, source_kind, source_label, now],
    )?;
    Ok(())
}

fn update_external_import_batch(
    conn: &Connection,
    batch_id: &str,
    status: &str,
    stats_json: &str,
    last_error: Option<&str>,
    completed_at_ms: Option<i64>,
) -> Result<()> {
    let now = now_ms();
    conn.execute(
        r#"UPDATE external_import_batches
           SET status = ?2,
               updated_at_ms = ?3,
               completed_at_ms = ?4,
               stats_json = ?5,
               last_error = ?6
           WHERE batch_id = ?1"#,
        params![batch_id, status, now, completed_at_ms, stats_json, last_error],
    )?;
    Ok(())
}

fn insert_external_document(
    conn: &Connection,
    key: &[u8; 32],
    batch_id: &str,
    doc: &CanonicalExternalDocument,
) -> Result<String> {
    let doc_id = uuid::Uuid::new_v4().to_string();
    let title_blob = encode_external_document_title(key, &doc_id, &doc.title)?;
    let body_blob = encode_external_document_body(key, &doc_id, &doc.body_markdown)?;
    let tags_json = serde_json::to_string(&doc.tags).unwrap_or_else(|_| "[]".to_string());
    let tags_blob = encode_external_document_tags(key, &doc_id, &tags_json)?;
    let checksum_sha256 = sha256_hex(doc.body_markdown.as_bytes());

    conn.execute(
        r#"INSERT INTO external_documents(
             doc_id, batch_id, external_origin_id, source_rel_path, title, body_markdown, tags_json,
             created_at_ms, updated_at_ms, checksum_sha256, is_deleted
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 0)"#,
        params![
            doc_id,
            batch_id,
            doc.external_origin_id,
            doc.source_rel_path,
            title_blob,
            body_blob,
            tags_blob,
            doc.created_at_ms,
            doc.updated_at_ms,
            checksum_sha256,
        ],
    )?;

    let chunks = split_attachment_text_into_chunks(&doc.body_markdown);
    if chunks.is_empty() && !doc.body_markdown.trim().is_empty() {
        let blob = encode_external_chunk_text(key, &doc_id, 0, doc.body_markdown.trim())?;
        conn.execute(
            r#"INSERT INTO external_document_chunks(doc_id, chunk_index, chunk_text, created_at_ms, updated_at_ms)
               VALUES (?1, 0, ?2, ?3, ?3)"#,
            params![doc_id, blob, now_ms()],
        )?;
    } else {
        let now = now_ms();
        for (chunk_index, (start_offset, end_offset)) in chunks.into_iter().enumerate() {
            if end_offset <= start_offset {
                continue;
            }
            let chunk_text = doc.body_markdown[start_offset..end_offset].trim();
            if chunk_text.is_empty() {
                continue;
            }
            let chunk_index_i64 = i64::try_from(chunk_index).unwrap_or(i64::MAX);
            let blob = encode_external_chunk_text(key, &doc_id, chunk_index_i64, chunk_text)?;
            conn.execute(
                r#"INSERT INTO external_document_chunks(doc_id, chunk_index, chunk_text, created_at_ms, updated_at_ms)
                   VALUES (?1, ?2, ?3, ?4, ?4)"#,
                params![doc_id, chunk_index_i64, blob, now],
            )?;
        }
    }

    Ok(doc_id)
}

fn copy_or_link_external_attachment(
    app_dir: &Path,
    conn: &Connection,
    key: &[u8; 32],
    source_path: &Path,
) -> Result<(String, bool, i64)> {
    let bytes = fs::read(source_path)?;
    let sha256 = sha256_hex(&bytes);
    let size_bytes = i64::try_from(bytes.len()).unwrap_or(i64::MAX);

    let existing: Option<(i64, String)> = conn
        .query_row(
            r#"SELECT ref_count, stored_path FROM external_attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    if existing.is_some() {
        conn.execute(
            r#"UPDATE external_attachments
               SET ref_count = ref_count + 1
               WHERE sha256 = ?1"#,
            params![sha256],
        )?;
        return Ok((sha256, false, size_bytes));
    }

    fs::create_dir_all(external_readonly_attachment_dir(app_dir))?;
    let rel_path = format!(
        "external_readonly/storage/attachments/{sha256}.bin"
    );
    let full_path = app_dir.join(&rel_path);
    let blob = encrypt_bytes(key, &bytes, &external_attachment_aad(&sha256))?;
    fs::write(full_path, blob)?;

    conn.execute(
        r#"INSERT INTO external_attachments(sha256, stored_path, size_bytes, mime_type, ref_count, created_at_ms)
           VALUES (?1, ?2, ?3, ?4, 1, ?5)"#,
        params![
            sha256,
            rel_path,
            size_bytes,
            infer_external_mime_type(source_path),
            now_ms(),
        ],
    )?;

    Ok((sha256, true, size_bytes))
}

fn link_external_attachment_to_document(
    conn: &Connection,
    doc_id: &str,
    sha256: &str,
    attachment_name: &str,
    ordinal: i64,
) -> Result<()> {
    conn.execute(
        r#"INSERT INTO external_document_attachments(doc_id, sha256, attachment_name, ordinal)
           VALUES (?1, ?2, ?3, ?4)"#,
        params![doc_id, sha256, attachment_name, ordinal],
    )?;
    Ok(())
}

fn cancel_requested(app_dir: &Path, batch_id: &str, should_cancel: &dyn Fn() -> bool) -> bool {
    should_cancel() || external_cancel_flag_path(app_dir, batch_id).exists()
}

fn delete_external_import_batch_internal(
    app_dir: &Path,
    conn: &Connection,
    batch_id: &str,
    remove_batch_row: bool,
    terminal_status: Option<&str>,
) -> Result<()> {
    let mut attachment_decrements = BTreeMap::<String, i64>::new();
    let mut stmt = conn.prepare(
        r#"SELECT a.sha256, COUNT(*)
           FROM external_document_attachments a
           JOIN external_documents d ON d.doc_id = a.doc_id
           WHERE d.batch_id = ?1
           GROUP BY a.sha256"#,
    )?;
    let mut rows = stmt.query(params![batch_id])?;
    while let Some(row) = rows.next()? {
        let sha256: String = row.get(0)?;
        let decrement: i64 = row.get(1)?;
        attachment_decrements.insert(sha256, decrement.max(0));
    }

    let space_ids = list_external_embedding_space_ids(conn)?;
    for space_id in space_ids {
        let table = external_chunk_embeddings_table(&space_id)?;
        if !sqlite_table_exists(conn, &table)? {
            continue;
        }
        conn.execute(
            &format!(
                r#"DELETE FROM "{table}"
                   WHERE doc_id IN (
                     SELECT doc_id FROM external_documents WHERE batch_id = ?1
                   )"#
            ),
            params![batch_id],
        )?;
    }

    let mut files_to_remove = Vec::<PathBuf>::new();
    for (sha256, decrement) in attachment_decrements {
        let existing: Option<(i64, String)> = conn
            .query_row(
                r#"SELECT ref_count, stored_path FROM external_attachments WHERE sha256 = ?1"#,
                params![sha256],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()?;
        let Some((ref_count, stored_path)) = existing else {
            continue;
        };
        if ref_count <= decrement {
            conn.execute(
                r#"DELETE FROM external_attachments WHERE sha256 = ?1"#,
                params![sha256],
            )?;
            files_to_remove.push(app_dir.join(stored_path));
        } else {
            conn.execute(
                r#"UPDATE external_attachments SET ref_count = ?2 WHERE sha256 = ?1"#,
                params![sha256, ref_count - decrement],
            )?;
        }
    }

    conn.execute(
        r#"DELETE FROM external_documents WHERE batch_id = ?1"#,
        params![batch_id],
    )?;

    if remove_batch_row {
        conn.execute(
            r#"DELETE FROM external_import_batches WHERE batch_id = ?1"#,
            params![batch_id],
        )?;
    } else if let Some(status) = terminal_status {
        update_external_import_batch(conn, batch_id, status, &build_external_stats_json(0, 0, 0, 0), None, Some(now_ms()))?;
    }

    for path in files_to_remove {
        let _ = best_effort_remove_external_path(&path);
    }
    let _ = best_effort_remove_external_path(&external_cancel_flag_path(app_dir, batch_id));
    Ok(())
}

pub fn delete_external_import_batch(app_dir: &Path, batch_id: &str) -> Result<()> {
    let conn = open_external_readonly_db(app_dir)?;
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = delete_external_import_batch_internal(app_dir, &conn, batch_id, true, None);
    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn run_external_import_with_callbacks(
    app_dir: &Path,
    key: &[u8; 32],
    source_path: &Path,
    on_event: &mut dyn FnMut(ExternalImportProgress),
    should_cancel: &dyn Fn() -> bool,
) -> Result<ExternalImportBatchSummary> {
    let materialized = materialize_external_import_source(app_dir, source_path)?;
    let parsed_result = parse_materialized_external_source(&materialized.root_dir, &materialized.source_label);
    let parsed = match parsed_result {
        Ok(parsed) => parsed,
        Err(e) => {
            cleanup_materialized_external_import_source(&materialized);
            return Err(e);
        }
    };

    let batch_id = uuid::Uuid::new_v4().to_string();
    let mut failed_count = 0i64;
    let mut copied_bytes = 0i64;
    let mut unique_attachment_shas = BTreeSet::<String>::new();

    let conn = open_external_readonly_db(app_dir)?;
    insert_external_import_batch(&conn, &batch_id, &parsed.detected_source_kind, &parsed.source_label)?;
    for diagnostic in &parsed.diagnostics {
        insert_external_import_diagnostic(
            &conn,
            &batch_id,
            &diagnostic.stage,
            &diagnostic.severity,
            &diagnostic.code,
            &diagnostic.message,
            diagnostic.source_rel_path.as_deref(),
        )?;
    }

    emit_external_import_progress(on_event, &batch_id, "preparing", 0, 1, 0, "in_progress");
    emit_external_import_progress(
        on_event,
        &batch_id,
        "scanning",
        i64::try_from(parsed.documents.len()).unwrap_or(i64::MAX),
        i64::try_from(parsed.documents.len()).unwrap_or(i64::MAX),
        0,
        "in_progress",
    );

    let result = (|| -> Result<ExternalImportBatchSummary> {
        let mut imported_docs = Vec::<(String, String, Vec<CanonicalExternalAttachmentRef>)>::new();
        let total_docs = i64::try_from(parsed.documents.len()).unwrap_or(i64::MAX);
        for (index, doc) in parsed.documents.iter().enumerate() {
            if cancel_requested(app_dir, &batch_id, should_cancel) {
                conn.execute_batch("BEGIN IMMEDIATE;")?;
                let cancel_result = delete_external_import_batch_internal(
                    app_dir,
                    &conn,
                    &batch_id,
                    false,
                    Some("cancelled"),
                );
                match cancel_result {
                    Ok(()) => conn.execute_batch("COMMIT;")?,
                    Err(e) => {
                        let _ = conn.execute_batch("ROLLBACK;");
                        return Err(e);
                    }
                }
                let summary = read_external_import_batch_summary(&conn, &batch_id)?;
                emit_external_import_progress(on_event, &batch_id, "rollback", 1, 1, failed_count, "cancelled");
                emit_external_import_progress(on_event, &batch_id, "cancelled", 1, 1, failed_count, "cancelled");
                return Ok(summary);
            }

            match insert_external_document(&conn, key, &batch_id, doc) {
                Ok(doc_id) => imported_docs.push((
                    doc_id,
                    doc.source_rel_path.clone(),
                    doc.attachments.clone(),
                )),
                Err(error) => {
                    failed_count += 1;
                    let message =
                        format!("failed to persist document {}: {error}", doc.source_rel_path);
                    let _ = insert_external_import_diagnostic(
                        &conn,
                        &batch_id,
                        "parsing",
                        "error",
                        "insert_external_document_failed",
                        &message,
                        Some(doc.source_rel_path.as_str()),
                    );
                }
            }
            emit_external_import_progress(
                on_event,
                &batch_id,
                "parsing",
                i64::try_from(index + 1).unwrap_or(i64::MAX),
                total_docs,
                failed_count,
                "in_progress",
            );
        }

        let total_attachment_refs = imported_docs
            .iter()
            .map(|(_, _, attachments)| attachments.len())
            .sum::<usize>();
        for (ordinal_base, (doc_id, source_rel_path, attachments)) in imported_docs.iter().enumerate() {
            let _ = ordinal_base;
            for (attachment_index, attachment) in attachments.iter().enumerate() {
                if cancel_requested(app_dir, &batch_id, should_cancel) {
                    conn.execute_batch("BEGIN IMMEDIATE;")?;
                    let cancel_result = delete_external_import_batch_internal(
                        app_dir,
                        &conn,
                        &batch_id,
                        false,
                        Some("cancelled"),
                    );
                    match cancel_result {
                        Ok(()) => conn.execute_batch("COMMIT;")?,
                        Err(e) => {
                            let _ = conn.execute_batch("ROLLBACK;");
                            return Err(e);
                        }
                    }
                    let summary = read_external_import_batch_summary(&conn, &batch_id)?;
                    emit_external_import_progress(on_event, &batch_id, "rollback", 1, 1, failed_count, "cancelled");
                    emit_external_import_progress(on_event, &batch_id, "cancelled", 1, 1, failed_count, "cancelled");
                    return Ok(summary);
                }

                match copy_or_link_external_attachment(app_dir, &conn, key, &attachment.source_path) {
                    Ok((sha256, inserted_new, size_bytes)) => {
                        if inserted_new {
                            copied_bytes = copied_bytes.saturating_add(size_bytes.max(0));
                        }
                        unique_attachment_shas.insert(sha256.clone());
                        if let Err(error) = link_external_attachment_to_document(
                            &conn,
                            doc_id,
                            &sha256,
                            &attachment.attachment_name,
                            i64::try_from(attachment_index).unwrap_or(i64::MAX),
                        ) {
                            failed_count += 1;
                            let message = format!(
                                "failed to link attachment {}: {error}",
                                attachment.source_path.display()
                            );
                            let _ = insert_external_import_diagnostic(
                                &conn,
                                &batch_id,
                                "copying_attachments",
                                "error",
                                "link_external_attachment_failed",
                                &message,
                                Some(source_rel_path.as_str()),
                            );
                        }
                    }
                    Err(error) => {
                        failed_count += 1;
                        let message = format!(
                            "failed to copy attachment {}: {error}",
                            attachment.source_path.display()
                        );
                        let _ = insert_external_import_diagnostic(
                            &conn,
                            &batch_id,
                            "copying_attachments",
                            "error",
                            "copy_external_attachment_failed",
                            &message,
                            Some(source_rel_path.as_str()),
                        );
                    }
                }
                let done = conn
                    .query_row(
                        r#"SELECT COUNT(*) FROM external_document_attachments a
                           JOIN external_documents d ON d.doc_id = a.doc_id
                           WHERE d.batch_id = ?1"#,
                        params![batch_id],
                        |row| row.get::<_, i64>(0),
                    )
                    .unwrap_or(0);
                emit_external_import_progress(
                    on_event,
                    &batch_id,
                    "copying_attachments",
                    done,
                    i64::try_from(total_attachment_refs).unwrap_or(i64::MAX),
                    failed_count,
                    "in_progress",
                );
            }
        }

        let total_chunks: i64 = conn.query_row(
            r#"SELECT COUNT(*)
               FROM external_document_chunks c
               JOIN external_documents d ON d.doc_id = c.doc_id
               WHERE d.batch_id = ?1"#,
            params![batch_id],
            |row| row.get(0),
        )?;

        let mut indexed = 0i64;
        loop {
            let processed = process_pending_external_document_embeddings_default(app_dir, key, 256)?;
            if processed == 0 {
                break;
            }
            indexed = indexed.saturating_add(i64::try_from(processed).unwrap_or(i64::MAX));
            emit_external_import_progress(
                on_event,
                &batch_id,
                "indexing_phase_a",
                indexed.min(total_chunks.max(0)),
                total_chunks,
                failed_count,
                "in_progress",
            );
        }
        emit_external_import_progress(on_event, &batch_id, "verifying", 1, 1, failed_count, "in_progress");

        let stats_json = build_external_stats_json(
            i64::try_from(parsed.documents.len()).unwrap_or(i64::MAX),
            i64::try_from(unique_attachment_shas.len()).unwrap_or(i64::MAX),
            failed_count,
            copied_bytes,
        );
        update_external_import_batch(
            &conn,
            &batch_id,
            "completed",
            &stats_json,
            None,
            Some(now_ms()),
        )?;

        let summary = read_external_import_batch_summary(&conn, &batch_id)?;
        emit_external_import_progress(on_event, &batch_id, "completed", 1, 1, failed_count, "completed");
        Ok(summary)
    })();

    cleanup_materialized_external_import_source(&materialized);

    match result {
        Ok(summary) => Ok(summary),
        Err(e) => {
            let message = e.to_string();
            let _ = insert_external_import_diagnostic(
                &conn,
                &batch_id,
                "import",
                "error",
                "external_import_failed",
                &message,
                None,
            );
            let stats_json = build_external_stats_json(0, 0, failed_count, copied_bytes);
            let _ = update_external_import_batch(&conn, &batch_id, "failed", &stats_json, Some(&message), Some(now_ms()));
            let _ = delete_external_import_batch_internal(app_dir, &conn, &batch_id, false, Some("failed"));
            Err(e)
        }
    }
}

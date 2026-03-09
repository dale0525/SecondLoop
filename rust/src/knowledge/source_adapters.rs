use anyhow::{anyhow, Result};
use rusqlite::Connection;

use crate::crypto::decrypt_bytes;
use crate::db;
use crate::knowledge::{
    normalize_text_for_source, ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeOriginType,
    KnowledgeRole, KnowledgeSourceKind, KnowledgeVersionSet,
};

fn snippet(text: &str, limit: usize) -> Option<String> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    let mut out = String::new();
    for ch in trimmed.chars() {
        if out.chars().count() >= limit {
            break;
        }
        out.push(ch);
    }
    if out.len() < trimmed.len() {
        out.push('…');
    }
    Some(out)
}

struct DocumentSeed {
    document_id: String,
    origin_type: KnowledgeOriginType,
    source_kind: KnowledgeSourceKind,
    role: KnowledgeRole,
    created_at_ms: i64,
    updated_at_ms: i64,
    anchors: KnowledgeAnchorSet,
    title: Option<String>,
    raw_text: String,
}

fn emit_document_if_text(
    emit: &mut impl FnMut(ContentKnowledgeDocument) -> Result<()>,
    seed: DocumentSeed,
) -> Result<()> {
    let trimmed = seed.raw_text.trim();
    if trimmed.is_empty() {
        return Ok(());
    }
    let normalized_text = normalize_text_for_source(seed.source_kind, trimmed);
    if normalized_text.trim().is_empty() {
        return Ok(());
    }
    emit(ContentKnowledgeDocument {
        document_id: seed.document_id,
        origin_type: seed.origin_type,
        source_kind: seed.source_kind,
        role: seed.role,
        language: None,
        quality_score: 1.0,
        created_at_ms: seed.created_at_ms,
        updated_at_ms: seed.updated_at_ms,
        versions: KnowledgeVersionSet::current(),
        anchors: seed.anchors,
        title: seed.title,
        summary: snippet(&normalized_text, 120),
        raw_text: trimmed.to_string(),
        normalized_text,
    })
}

fn canonical_source_kind_name(source_kind: KnowledgeSourceKind) -> Result<String> {
    let value = serde_json::to_value(source_kind)
        .map_err(|error| anyhow!("serialize knowledge source kind: {error}"))?;
    value
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| anyhow!("knowledge source kind did not serialize to a string"))
}

fn collect_message_documents(
    conn: &Connection,
    key: &[u8; 32],
    emit: &mut impl FnMut(ContentKnowledgeDocument) -> Result<()>,
) -> Result<()> {
    let mut stmt = conn.prepare(
        r#"SELECT id, conversation_id, content, created_at, updated_at
           FROM messages
           WHERE COALESCE(is_deleted, 0) = 0
             -- Match legacy semantic-index semantics: NULL/1 remain indexable,
             -- while explicit non-memory rows stay excluded.
             AND COALESCE(is_memory, 1) = 1
           ORDER BY created_at ASC"#,
    )?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        let conversation_id: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;
        let created_at_ms: i64 = row.get(3)?;
        let updated_at_ms: i64 = row.get(4)?;
        let content_bytes = match decrypt_bytes(key, &content_blob, b"message.content") {
            Ok(bytes) => bytes,
            Err(_) => continue,
        };
        let content = match String::from_utf8(content_bytes) {
            Ok(value) => value,
            Err(_) => continue,
        };
        emit_document_if_text(
            emit,
            DocumentSeed {
                document_id: format!("message:{message_id}"),
                origin_type: KnowledgeOriginType::Message,
                source_kind: KnowledgeSourceKind::RawText,
                role: KnowledgeRole::Body,
                created_at_ms,
                updated_at_ms,
                anchors: KnowledgeAnchorSet {
                    message_id: Some(message_id),
                    conversation_id: Some(conversation_id),
                    ..KnowledgeAnchorSet::default()
                },
                title: None,
                raw_text: content,
            },
        )?;
    }
    Ok(())
}

fn attachment_source_candidates(
    payload: &serde_json::Value,
) -> Vec<(KnowledgeSourceKind, KnowledgeRole, String)> {
    let mut out = Vec::<(KnowledgeSourceKind, KnowledgeRole, String)>::new();
    let push_text = |out: &mut Vec<(KnowledgeSourceKind, KnowledgeRole, String)>,
                     kind: KnowledgeSourceKind,
                     role: KnowledgeRole,
                     value: Option<&str>| {
        let Some(value) = value.map(str::trim).filter(|v| !v.is_empty()) else {
            return;
        };
        if out
            .iter()
            .any(|(existing_kind, _, existing)| *existing_kind == kind && existing == value)
        {
            return;
        }
        out.push((kind, role, value.to_string()));
    };

    push_text(
        &mut out,
        KnowledgeSourceKind::ExtractedText,
        KnowledgeRole::Evidence,
        payload
            .get("extracted_text_full")
            .and_then(|v| v.as_str())
            .or_else(|| {
                payload
                    .get("extracted_text_excerpt")
                    .and_then(|v| v.as_str())
            }),
    );
    push_text(
        &mut out,
        KnowledgeSourceKind::ReadableText,
        KnowledgeRole::Body,
        payload
            .get("readable_text_full")
            .and_then(|v| v.as_str())
            .or_else(|| {
                payload
                    .get("readable_text_excerpt")
                    .and_then(|v| v.as_str())
            }),
    );
    push_text(
        &mut out,
        KnowledgeSourceKind::OcrText,
        KnowledgeRole::Evidence,
        payload
            .get("ocr_text_full")
            .and_then(|v| v.as_str())
            .or_else(|| payload.get("ocr_text_excerpt").and_then(|v| v.as_str()))
            .or_else(|| payload.get("ocr_text").and_then(|v| v.as_str())),
    );
    push_text(
        &mut out,
        KnowledgeSourceKind::Transcript,
        KnowledgeRole::Evidence,
        payload
            .get("transcript_full")
            .and_then(|v| v.as_str())
            .or_else(|| payload.get("transcript_excerpt").and_then(|v| v.as_str())),
    );
    push_text(
        &mut out,
        KnowledgeSourceKind::ImageUnderstanding,
        KnowledgeRole::Caption,
        payload.get("caption_long").and_then(|v| v.as_str()),
    );
    out
}

fn collect_attachment_documents(
    conn: &Connection,
    key: &[u8; 32],
    emit: &mut impl FnMut(ContentKnowledgeDocument) -> Result<()>,
) -> Result<()> {
    let mut stmt = conn.prepare(
        r#"SELECT sha256, created_at
           FROM attachments
           ORDER BY created_at ASC, sha256 ASC"#,
    )?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let attachment_sha256: String = row.get(0)?;
        let created_at_ms: i64 = row.get(1)?;
        let updated_at_ms = created_at_ms;
        let metadata = db::read_attachment_metadata(conn, key, &attachment_sha256)?;
        let source_filename = metadata.as_ref().and_then(|value| {
            value
                .title
                .clone()
                .or_else(|| value.filenames.first().cloned())
        });
        let anchors = KnowledgeAnchorSet {
            attachment_sha256: Some(attachment_sha256.clone()),
            source_filename: source_filename.clone(),
            ..KnowledgeAnchorSet::default()
        };

        if let Some(metadata) = metadata {
            let mut metadata_lines = Vec::<String>::new();
            if let Some(title) = metadata.title.filter(|value| !value.trim().is_empty()) {
                metadata_lines.push(format!("title: {title}"));
            }
            if !metadata.filenames.is_empty() {
                metadata_lines.push(format!("filenames: {}", metadata.filenames.join(", ")));
            }
            if !metadata_lines.is_empty() {
                emit_document_if_text(
                    emit,
                    DocumentSeed {
                        document_id: format!("attachment:{attachment_sha256}:metadata"),
                        origin_type: KnowledgeOriginType::Attachment,
                        source_kind: KnowledgeSourceKind::Metadata,
                        role: KnowledgeRole::Metadata,
                        created_at_ms,
                        updated_at_ms,
                        anchors: anchors.clone(),
                        title: source_filename.clone(),
                        raw_text: metadata_lines.join("\n"),
                    },
                )?;
            }
        }

        let payload_json =
            db::read_attachment_annotation_payload_json(conn, key, &attachment_sha256)?;
        let Some(payload_json) = payload_json else {
            continue;
        };
        let payload: serde_json::Value = serde_json::from_str(&payload_json)
            .map_err(|error| anyhow!("invalid attachment annotation payload json: {error}"))?;
        for (source_kind, role, text) in attachment_source_candidates(&payload) {
            let source_kind_name = canonical_source_kind_name(source_kind)?;
            emit_document_if_text(
                emit,
                DocumentSeed {
                    document_id: format!("attachment:{attachment_sha256}:{source_kind_name}"),
                    origin_type: KnowledgeOriginType::Attachment,
                    source_kind,
                    role,
                    created_at_ms,
                    updated_at_ms,
                    anchors: anchors.clone(),
                    title: source_filename.clone(),
                    raw_text: text,
                },
            )?;
        }
    }
    Ok(())
}

fn decrypt_external_text(key: &[u8; 32], aad: Vec<u8>, blob: &[u8]) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &aad)?;
    String::from_utf8(bytes).map_err(|_| anyhow!("external document text is not valid utf-8"))
}

fn collect_external_documents(
    conn: &Connection,
    key: &[u8; 32],
    emit: &mut impl FnMut(ContentKnowledgeDocument) -> Result<()>,
) -> Result<()> {
    let app_dir = crate::db::app_dir_from_conn(conn)?;
    let external_conn = db::open_external_readonly_db(&app_dir)?;
    let mut stmt = external_conn.prepare(
        r#"SELECT doc_id, source_rel_path, title, body_markdown, created_at_ms, updated_at_ms
           FROM external_documents
           WHERE COALESCE(is_deleted, 0) = 0
           ORDER BY updated_at_ms DESC, doc_id ASC"#,
    )?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let doc_id: String = row.get(0)?;
        let source_rel_path: Option<String> = row.get(1)?;
        let title_blob: Vec<u8> = row.get(2)?;
        let body_blob: Vec<u8> = row.get(3)?;
        let created_at_ms: i64 = row.get(4)?;
        let updated_at_ms: i64 = row.get(5)?;
        let title = match decrypt_external_text(
            key,
            format!("external_document.title:{doc_id}").into_bytes(),
            &title_blob,
        ) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let body = match decrypt_external_text(
            key,
            format!("external_document.body:{doc_id}").into_bytes(),
            &body_blob,
        ) {
            Ok(value) => value,
            Err(_) => continue,
        };
        emit_document_if_text(
            emit,
            DocumentSeed {
                document_id: format!("external:{doc_id}"),
                origin_type: KnowledgeOriginType::ImportedExternal,
                source_kind: KnowledgeSourceKind::ReadableText,
                role: KnowledgeRole::Body,
                created_at_ms,
                updated_at_ms,
                anchors: KnowledgeAnchorSet {
                    source_filename: source_rel_path,
                    ..KnowledgeAnchorSet::default()
                },
                title: snippet(&title, 80),
                raw_text: body,
            },
        )?;
    }
    Ok(())
}

pub fn visit_source_knowledge_documents(
    conn: &Connection,
    key: &[u8; 32],
    mut emit: impl FnMut(ContentKnowledgeDocument) -> Result<()>,
) -> Result<()> {
    collect_message_documents(conn, key, &mut emit)?;
    collect_attachment_documents(conn, key, &mut emit)?;
    collect_external_documents(conn, key, &mut emit)?;
    Ok(())
}

pub fn collect_source_knowledge_documents(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Vec<ContentKnowledgeDocument>> {
    let mut documents = Vec::<ContentKnowledgeDocument>::new();
    visit_source_knowledge_documents(conn, key, |document| {
        documents.push(document);
        Ok(())
    })?;
    documents.sort_by(|left, right| {
        left.created_at_ms
            .cmp(&right.created_at_ms)
            .then_with(|| left.document_id.cmp(&right.document_id))
    });
    Ok(documents)
}

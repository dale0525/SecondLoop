use anyhow::Result;
use rusqlite::Connection;

use crate::db;

const RESOURCES_CATALOG_CAP: usize = 20;
const CHUNK_EVIDENCE_CAP: usize = 12;

#[derive(Clone, Debug)]
pub(crate) struct AttachmentChunkCandidate {
    pub(crate) attachment_sha256: String,
    pub(crate) kind: String,
    pub(crate) chunk_index: i64,
    pub(crate) created_at_ms: i64,
    pub(crate) distance: f64,
    pub(crate) text: String,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct AttachmentResourcesBundle {
    pub(crate) chunks: Vec<AttachmentChunkCandidate>,
    pub(crate) catalog_markdown: Option<String>,
}

fn safe_attachment_label(raw: &str) -> String {
    let cleaned = raw
        .trim()
        .replace('[', "(")
        .replace(']', ")")
        .replace(['\n', '\r'], " ");
    if cleaned.is_empty() {
        return "Attachment".to_string();
    }

    cleaned.chars().take(120).collect()
}

fn attachment_label(conn: &Connection, key: &[u8; 32], sha256: &str) -> String {
    if let Ok(Some(meta)) = db::read_attachment_metadata(conn, key, sha256) {
        if let Some(title) = meta.title {
            if !title.trim().is_empty() {
                return safe_attachment_label(&title);
            }
        }
        if let Some(filename) = meta.filenames.first() {
            if !filename.trim().is_empty() {
                return safe_attachment_label(filename);
            }
        }
    }

    let short_sha: String = sha256.chars().take(8).collect();
    format!("Attachment {short_sha}")
}

fn chunk_citation_link(sha: &str, kind: &str, chunk_index: i64) -> String {
    format!("secondloop://attachment/{sha}?kind={kind}&chunk={chunk_index}")
}

fn build_catalog_markdown_from_attachment_shas(
    conn: &Connection,
    key: &[u8; 32],
    resource_shas: Vec<String>,
    hits: &[db::SimilarAttachmentChunk],
) -> Result<Option<String>> {
    if resource_shas.is_empty() {
        return Ok(None);
    }

    let mut out = String::new();
    out.push_str("Resources catalog (attachments):\n");
    for sha in &resource_shas {
        let label = attachment_label(conn, key, sha);
        out.push_str(&format!("- [{}](secondloop://attachment/{})\n", label, sha));
    }

    let mut chunk_lines = 0usize;
    if !hits.is_empty() {
        out.push_str("\nRelevant attachment chunks:\n");
        for hit in hits {
            let label = attachment_label(conn, key, &hit.attachment_sha256);
            let citation = chunk_citation_link(&hit.attachment_sha256, &hit.kind, hit.chunk_index);
            out.push_str(&format!(
                "- [{} · {}#{}]({}): {}\n",
                label, hit.kind, hit.chunk_index, citation, hit.snippet
            ));
            chunk_lines += 1;
            if chunk_lines >= CHUNK_EVIDENCE_CAP {
                break;
            }
        }
    }

    Ok(Some(out))
}

fn build_catalog_markdown(
    conn: &Connection,
    key: &[u8; 32],
    hits: &[db::SimilarAttachmentChunk],
) -> Result<Option<String>> {
    let mut resource_shas = Vec::<String>::new();
    let mut seen = std::collections::HashSet::<String>::new();

    for hit in hits {
        if seen.insert(hit.attachment_sha256.clone()) {
            resource_shas.push(hit.attachment_sha256.clone());
            if resource_shas.len() >= RESOURCES_CATALOG_CAP {
                break;
            }
        }
    }

    build_catalog_markdown_from_attachment_shas(conn, key, resource_shas, hits)
}

fn bundle_from_hits(
    conn: &Connection,
    key: &[u8; 32],
    hits: Vec<db::SimilarAttachmentChunk>,
) -> Result<AttachmentResourcesBundle> {
    let mut chunks = Vec::<AttachmentChunkCandidate>::new();
    for hit in &hits {
        let chunk_text = db::read_attachment_chunk_text(
            conn,
            key,
            &hit.attachment_sha256,
            &hit.kind,
            hit.chunk_index,
        )
        .unwrap_or_else(|_| hit.snippet.clone());

        if chunk_text.trim().is_empty() {
            continue;
        }

        let created_at_ms = db::read_attachment_by_sha256(conn, &hit.attachment_sha256)?
            .map(|a| a.created_at_ms)
            .unwrap_or(0);

        chunks.push(AttachmentChunkCandidate {
            attachment_sha256: hit.attachment_sha256.clone(),
            kind: hit.kind.clone(),
            chunk_index: hit.chunk_index,
            created_at_ms,
            distance: hit.distance,
            text: chunk_text,
        });
    }

    let catalog_markdown = build_catalog_markdown(conn, key, &hits)?;
    Ok(AttachmentResourcesBundle {
        chunks,
        catalog_markdown,
    })
}

pub(crate) fn collect_attachment_resources_default(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    top_k: usize,
) -> Result<AttachmentResourcesBundle> {
    db::process_attachment_text_chunks(conn, key, 256)?;
    db::process_pending_attachment_chunk_embeddings_default(conn, key, 2048)?;

    let hit_limit = if top_k == 0 {
        8
    } else {
        (top_k.saturating_mul(8)).min(200).max(top_k)
    };

    let hits = db::search_similar_attachment_chunks_default(conn, key, question, hit_limit)?;
    bundle_from_hits(conn, key, hits)
}

pub(crate) fn collect_attachment_resources_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &std::path::Path,
    question: &str,
    top_k: usize,
) -> Result<AttachmentResourcesBundle> {
    db::process_attachment_text_chunks(conn, key, 256)?;
    db::process_pending_attachment_chunk_embeddings_active(conn, key, app_dir, 2048)?;

    let hit_limit = if top_k == 0 {
        8
    } else {
        (top_k.saturating_mul(8)).min(200).max(top_k)
    };

    let hits =
        db::search_similar_attachment_chunks_active(conn, key, app_dir, question, hit_limit)?;
    bundle_from_hits(conn, key, hits)
}

pub(crate) fn collect_attachment_resources_by_embedding(
    conn: &Connection,
    key: &[u8; 32],
    model_name: &str,
    query_vector: &[f32],
    top_k: usize,
) -> Result<AttachmentResourcesBundle> {
    let hit_limit = if top_k == 0 {
        8
    } else {
        (top_k.saturating_mul(8)).min(200).max(top_k)
    };

    let hits = db::search_similar_attachment_chunks_by_embedding(
        conn,
        key,
        model_name,
        query_vector,
        hit_limit,
    )?;
    bundle_from_hits(conn, key, hits)
}

pub(crate) fn collect_attachment_resources_for_attachment_shas(
    conn: &Connection,
    key: &[u8; 32],
    attachment_shas: Vec<String>,
) -> Result<AttachmentResourcesBundle> {
    let mut resource_shas = Vec::<String>::new();
    let mut seen = std::collections::HashSet::<String>::new();
    for sha in attachment_shas {
        if !seen.insert(sha.clone()) {
            continue;
        }
        resource_shas.push(sha);
        if resource_shas.len() >= RESOURCES_CATALOG_CAP {
            break;
        }
    }

    let catalog_markdown =
        build_catalog_markdown_from_attachment_shas(conn, key, resource_shas, &[])?;
    Ok(AttachmentResourcesBundle {
        chunks: Vec::new(),
        catalog_markdown,
    })
}

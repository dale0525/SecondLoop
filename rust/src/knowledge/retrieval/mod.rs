use anyhow::Result;
use rusqlite::Connection;

use crate::knowledge::{
    list_knowledge_documents, list_knowledge_units, ContentKnowledgeDocument, KnowledgeAnchorSet,
    KnowledgeContextBlock, KnowledgeQueryScope, KnowledgeRetrievalLayer, KnowledgeRole,
    KnowledgeSearchResult, KnowledgeSourceKind, KnowledgeUnit, KnowledgeUnitKind,
};

pub(crate) mod pack;
pub mod query;
pub(crate) mod recall;
pub(crate) mod rerank;

pub(crate) use pack::pack_context_blocks;
pub use query::{normalize_retrieval_request, NormalizedRetrievalRequest};
pub(crate) use recall::recall_knowledge_candidates;
pub(crate) use rerank::rerank_knowledge_candidates;

#[cfg(test)]
mod eval_tests;
#[cfg(test)]
mod pack_tests;
#[cfg(test)]
mod query_tests;
#[cfg(test)]
mod recall_tests;
#[cfg(test)]
mod rerank_tests;
#[cfg(test)]
pub(crate) mod test_support;

const READ_PAGE_SIZE: usize = 128;

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct KnowledgeCandidate {
    pub(crate) document: ContentKnowledgeDocument,
    pub(crate) unit: Option<KnowledgeUnit>,
    pub(crate) layer: KnowledgeRetrievalLayer,
    pub(crate) role: KnowledgeRole,
    pub(crate) unit_kind: Option<KnowledgeUnitKind>,
    pub(crate) unit_id: Option<String>,
    pub(crate) prev_unit_id: Option<String>,
    pub(crate) next_unit_id: Option<String>,
    pub(crate) raw_text: String,
    pub(crate) normalized_text: String,
    pub(crate) semantic_score: f64,
    pub(crate) lexical_score: f64,
    pub(crate) score: f64,
    pub(crate) expansion_score: f64,
}

impl KnowledgeCandidate {
    pub(crate) fn from_document(
        document: &ContentKnowledgeDocument,
        semantic_score: f64,
        lexical_score: f64,
    ) -> Self {
        Self {
            document: document.clone(),
            unit: None,
            layer: KnowledgeRetrievalLayer::Document,
            role: document.role,
            unit_kind: None,
            unit_id: None,
            prev_unit_id: None,
            next_unit_id: None,
            raw_text: document.raw_text.clone(),
            normalized_text: document.normalized_text.clone(),
            semantic_score,
            lexical_score,
            score: semantic_score.max(lexical_score),
            expansion_score: 0.0,
        }
    }

    pub(crate) fn from_unit(
        document: &ContentKnowledgeDocument,
        unit: &KnowledgeUnit,
        layer: KnowledgeRetrievalLayer,
        semantic_score: f64,
        lexical_score: f64,
    ) -> Self {
        Self {
            document: document.clone(),
            unit: Some(unit.clone()),
            layer,
            role: unit.role,
            unit_kind: Some(unit.unit_kind),
            unit_id: Some(unit.unit_id.clone()),
            prev_unit_id: unit.prev_unit_id.clone(),
            next_unit_id: unit.next_unit_id.clone(),
            raw_text: unit.raw_text.clone(),
            normalized_text: unit.normalized_text.clone(),
            semantic_score,
            lexical_score,
            score: semantic_score.max(lexical_score),
            expansion_score: 0.0,
        }
    }

    pub(crate) fn key(&self) -> String {
        match self.unit_id.as_deref() {
            Some(unit_id) => format!("unit:{unit_id}"),
            None => format!("document:{}", self.document.document_id),
        }
    }

    pub(crate) fn anchors(&self) -> &KnowledgeAnchorSet {
        self.unit
            .as_ref()
            .map(|unit| &unit.anchors)
            .unwrap_or(&self.document.anchors)
    }

    pub(crate) fn created_at_ms(&self) -> i64 {
        self.unit
            .as_ref()
            .map(|unit| unit.created_at_ms)
            .unwrap_or(self.document.created_at_ms)
    }

    pub(crate) fn updated_at_ms(&self) -> i64 {
        self.unit
            .as_ref()
            .map(|unit| unit.updated_at_ms)
            .unwrap_or(self.document.updated_at_ms)
    }

    pub(crate) fn source_kind(&self) -> KnowledgeSourceKind {
        self.unit
            .as_ref()
            .map(|unit| unit.source_kind)
            .unwrap_or(self.document.source_kind)
    }
}

fn matches_time_window(
    anchors: &KnowledgeAnchorSet,
    created_at_ms: i64,
    request: &NormalizedRetrievalRequest,
) -> bool {
    if request.time_start_ms.is_none() && request.time_end_ms.is_none() {
        return true;
    }
    let query_start = request.time_start_ms.unwrap_or(i64::MIN);
    let query_end = request.time_end_ms.unwrap_or(i64::MAX);
    let target_start = anchors.start_ms.unwrap_or(created_at_ms);
    let target_end = anchors.end_ms.unwrap_or(target_start);
    target_end >= query_start && target_start <= query_end
}

fn attachment_belongs_to_conversation(
    conn: &Connection,
    attachment_sha256: &str,
    conversation_id: &str,
) -> Result<bool> {
    let count: i64 = conn.query_row(
        r#"SELECT COUNT(*)
           FROM message_attachments ma
           JOIN messages m ON m.id = ma.message_id
           WHERE ma.attachment_sha256 = ?1
             AND m.conversation_id = ?2
             AND COALESCE(m.is_deleted, 0) = 0"#,
        rusqlite::params![attachment_sha256, conversation_id],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}

pub(crate) fn load_scoped_documents(
    conn: &Connection,
    key: &[u8; 32],
    request: &NormalizedRetrievalRequest,
) -> Result<Vec<ContentKnowledgeDocument>> {
    let mut offset = 0usize;
    let mut documents = Vec::<ContentKnowledgeDocument>::new();
    loop {
        let page = list_knowledge_documents(conn, key, READ_PAGE_SIZE, offset)?;
        if page.is_empty() {
            break;
        }
        let count = page.len();
        for document in page {
            if !request.source_filters.is_empty()
                && !request.source_filters.contains(&document.source_kind)
            {
                continue;
            }
            if !matches_time_window(&document.anchors, document.created_at_ms, request) {
                continue;
            }
            let in_scope = match request.scope {
                KnowledgeQueryScope::All => true,
                KnowledgeQueryScope::Conversation => request
                    .conversation_id
                    .as_deref()
                    .map(|expected| {
                        document.anchors.conversation_id.as_deref() == Some(expected)
                            || document
                                .anchors
                                .attachment_sha256
                                .as_deref()
                                .and_then(|attachment_sha256| {
                                    attachment_belongs_to_conversation(
                                        conn,
                                        attachment_sha256,
                                        expected,
                                    )
                                    .ok()
                                })
                                .unwrap_or(false)
                    })
                    .unwrap_or(false),
                KnowledgeQueryScope::Document => request
                    .document_id
                    .as_deref()
                    .map(|expected| expected == document.document_id)
                    .unwrap_or(false),
            };
            if in_scope {
                documents.push(document);
            }
        }
        if count < READ_PAGE_SIZE {
            break;
        }
        offset += count;
    }
    Ok(documents)
}

pub(crate) fn load_document_units(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    unit_kind: KnowledgeUnitKind,
) -> Result<Vec<KnowledgeUnit>> {
    let mut units = Vec::<KnowledgeUnit>::new();
    let mut offset = 0usize;
    loop {
        let page = list_knowledge_units(
            conn,
            key,
            document_id,
            Some(unit_kind),
            READ_PAGE_SIZE,
            offset,
        )?;
        if page.is_empty() {
            break;
        }
        let count = page.len();
        units.extend(page);
        if count < READ_PAGE_SIZE {
            break;
        }
        offset += count;
    }
    Ok(units)
}

fn trim_snippet(text: &str, limit: usize) -> String {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let out = trimmed.chars().take(limit).collect::<String>();
    if out.chars().count() < trimmed.chars().count() {
        format!("{out}…")
    } else {
        out
    }
}

pub(crate) fn build_search_snippet(text: &str, normalized_query: &str) -> String {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if normalized_query.trim().is_empty() {
        return trim_snippet(trimmed, 220);
    }
    let normalized_text = query::normalized_text_for_matching(trimmed);
    if normalized_text.contains(normalized_query) {
        return trim_snippet(trimmed, 220);
    }
    for token in normalized_query.split_whitespace() {
        if token.len() < 2 {
            continue;
        }
        if normalized_text.contains(token) {
            return trim_snippet(trimmed, 220);
        }
    }
    trim_snippet(trimmed, 220)
}

pub(crate) fn anchor_summary(anchors: &KnowledgeAnchorSet) -> String {
    let mut parts = Vec::<String>::new();
    if let Some(message_id) = anchors.message_id.as_deref() {
        parts.push(format!("message_id={message_id}"));
    }
    if let Some(conversation_id) = anchors.conversation_id.as_deref() {
        parts.push(format!("conversation_id={conversation_id}"));
    }
    if let Some(attachment_sha256) = anchors.attachment_sha256.as_deref() {
        parts.push(format!("attachment_sha256={attachment_sha256}"));
    }
    if let Some(page_index) = anchors.page_index {
        parts.push(format!("page_index={page_index}"));
    }
    if let Some(frame_index) = anchors.frame_index {
        parts.push(format!("frame_index={frame_index}"));
    }
    if let Some(start_ms) = anchors.start_ms {
        parts.push(format!("start_ms={start_ms}"));
    }
    if let Some(end_ms) = anchors.end_ms {
        parts.push(format!("end_ms={end_ms}"));
    }
    if let Some(speaker) = anchors.speaker.as_deref() {
        parts.push(format!("speaker={speaker}"));
    }
    if let Some(section_label) = anchors.section_label.as_deref() {
        parts.push(format!("section_label={section_label}"));
    }
    if let Some(source_filename) = anchors.source_filename.as_deref() {
        parts.push(format!("source_filename={source_filename}"));
    }
    if parts.is_empty() {
        "anchors: none".to_string()
    } else {
        format!("anchors: {}", parts.join(" "))
    }
}

fn candidate_to_search_result(
    candidate: &KnowledgeCandidate,
    request: &NormalizedRetrievalRequest,
) -> KnowledgeSearchResult {
    KnowledgeSearchResult {
        document_id: candidate.document.document_id.clone(),
        unit_id: candidate.unit_id.clone(),
        unit_kind: candidate.unit_kind,
        layer: candidate.layer,
        source_kind: candidate.source_kind(),
        role: candidate.role,
        title: candidate.document.title.clone(),
        summary: candidate.document.summary.clone(),
        snippet: build_search_snippet(&candidate.raw_text, &request.normalized_query),
        score: candidate.score,
        semantic_score: candidate.semantic_score,
        lexical_score: candidate.lexical_score,
        anchors: candidate.anchors().clone(),
        created_at_ms: candidate.created_at_ms(),
        updated_at_ms: candidate.updated_at_ms(),
    }
}

pub fn retrieve_context_blocks(
    conn: &Connection,
    key: &[u8; 32],
    request: &NormalizedRetrievalRequest,
) -> Result<Vec<KnowledgeContextBlock>> {
    let recalled = recall_knowledge_candidates(conn, key, request)?;
    let reranked = rerank_knowledge_candidates(conn, key, request, recalled)?;
    Ok(pack_context_blocks(request, &reranked))
}

pub fn search_knowledge(
    conn: &Connection,
    key: &[u8; 32],
    request: &NormalizedRetrievalRequest,
) -> Result<Vec<KnowledgeSearchResult>> {
    let recalled = recall_knowledge_candidates(conn, key, request)?;
    let reranked = rerank_knowledge_candidates(conn, key, request, recalled)?;
    Ok(reranked
        .into_iter()
        .take(request.top_k)
        .map(|candidate| candidate_to_search_result(&candidate, request))
        .collect())
}

pub fn search_document_knowledge(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    query: &str,
    limit: usize,
) -> Result<Vec<KnowledgeSearchResult>> {
    let request = normalize_retrieval_request(
        query,
        None,
        Some(document_id.to_string()),
        Some(limit.max(1)),
        None,
        None,
    );
    search_knowledge(conn, key, &request)
}

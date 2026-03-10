use serde::{Deserialize, Serialize};

use crate::knowledge::{KnowledgeQueryScope, KnowledgeSourceKind};

const DEFAULT_TOP_K: usize = 8;
const DEFAULT_TOKEN_BUDGET: usize = 1200;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct NormalizedRetrievalRequest {
    pub query_text: String,
    pub normalized_query: String,
    pub language_hint: Option<String>,
    pub scope: KnowledgeQueryScope,
    pub conversation_id: Option<String>,
    pub document_id: Option<String>,
    pub source_filters: Vec<KnowledgeSourceKind>,
    pub top_k: usize,
    pub candidate_limit: usize,
    pub token_budget: usize,
    pub time_start_ms: Option<i64>,
    pub time_end_ms: Option<i64>,
}

fn normalize_search_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        if ch.is_alphanumeric() {
            out.extend(ch.to_lowercase());
        } else {
            out.push(' ');
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn parse_scope(value: &str) -> Option<KnowledgeQueryScope> {
    match value.trim().to_lowercase().as_str() {
        "all" | "global" => Some(KnowledgeQueryScope::All),
        "conversation" | "thread" => Some(KnowledgeQueryScope::Conversation),
        "document" | "doc" => Some(KnowledgeQueryScope::Document),
        _ => None,
    }
}

fn parse_source_kind(value: &str) -> Option<KnowledgeSourceKind> {
    serde_json::from_str(&format!("\"{}\"", value.trim().to_lowercase())).ok()
}

pub(crate) fn normalized_text_for_matching(text: &str) -> String {
    normalize_search_text(text)
}

pub fn normalize_retrieval_request(
    query: &str,
    conversation_id: Option<String>,
    document_id: Option<String>,
    top_k: Option<usize>,
    token_budget: Option<usize>,
    source_filters_override: Option<Vec<KnowledgeSourceKind>>,
) -> NormalizedRetrievalRequest {
    let mut language_hint = None;
    let mut scope_hint = None;
    let mut time_start_ms = None;
    let mut time_end_ms = None;
    let mut source_filters = Vec::<KnowledgeSourceKind>::new();
    let mut kept = Vec::<String>::new();

    for token in query.split_whitespace() {
        if let Some(value) = token
            .strip_prefix("lang:")
            .or_else(|| token.strip_prefix("language:"))
        {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                language_hint = Some(trimmed.to_lowercase());
            }
            continue;
        }
        if let Some(value) = token.strip_prefix("scope:") {
            scope_hint = parse_scope(value);
            continue;
        }
        if let Some(value) = token
            .strip_prefix("from:")
            .or_else(|| token.strip_prefix("after:"))
        {
            time_start_ms = value.parse::<i64>().ok();
            continue;
        }
        if let Some(value) = token
            .strip_prefix("to:")
            .or_else(|| token.strip_prefix("before:"))
        {
            time_end_ms = value.parse::<i64>().ok();
            continue;
        }
        if let Some(value) = token
            .strip_prefix("source:")
            .or_else(|| token.strip_prefix("sources:"))
        {
            for item in value.split(',') {
                if let Some(source_kind) = parse_source_kind(item) {
                    if !source_filters.contains(&source_kind) {
                        source_filters.push(source_kind);
                    }
                }
            }
            continue;
        }
        kept.push(token.trim().to_string());
    }

    if let Some(override_filters) = source_filters_override {
        source_filters = override_filters;
    }

    let query_text = kept
        .into_iter()
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    let normalized_query = normalize_search_text(&query_text);
    let scope = scope_hint.unwrap_or_else(|| {
        if document_id.is_some() {
            KnowledgeQueryScope::Document
        } else if conversation_id.is_some() {
            KnowledgeQueryScope::Conversation
        } else {
            KnowledgeQueryScope::All
        }
    });
    let top_k = top_k.unwrap_or(DEFAULT_TOP_K).max(1);
    let candidate_limit = top_k.saturating_mul(6).max(top_k);

    NormalizedRetrievalRequest {
        query_text,
        normalized_query,
        language_hint,
        scope,
        conversation_id,
        document_id,
        source_filters,
        top_k,
        candidate_limit,
        token_budget: token_budget.unwrap_or(DEFAULT_TOKEN_BUDGET).max(1),
        time_start_ms,
        time_end_ms,
    }
}

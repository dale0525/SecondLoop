use std::collections::{BTreeMap, BTreeSet};

use anyhow::Result;
use rusqlite::Connection;

use crate::knowledge::{
    ContentKnowledgeDocument, KnowledgeClaim, KnowledgeClaimStatus, KnowledgeClaimTimeScope,
    KnowledgeClaimType, KnowledgeOriginType, KnowledgePage, KnowledgePageType,
};

#[derive(Clone, Debug)]
pub(crate) struct CompiledKnowledgePageRecord {
    pub page: KnowledgePage,
    pub source_document_ids: Vec<String>,
    pub claim_ids: Vec<String>,
}

pub fn refresh_knowledge_pages(conn: &Connection, key: &[u8; 32]) -> Result<Vec<KnowledgePage>> {
    let generated_documents = crate::knowledge::list_knowledge_documents_by_origin(
        conn,
        key,
        KnowledgeOriginType::Generated,
        512,
        0,
    )?;
    let claims = build_claims_from_documents(&generated_documents);
    let compiled_pages = compile_pages_from_claims(&generated_documents, &claims);
    crate::db::replace_knowledge_claims(conn, key, &claims)?;
    crate::db::upsert_compiled_knowledge_pages(conn, key, &compiled_pages)?;
    let page_ids = compiled_pages
        .iter()
        .map(|item| item.page.page_id.clone())
        .collect::<Vec<_>>();
    crate::db::mark_missing_knowledge_pages_removed(conn, key, &page_ids)?;
    Ok(compiled_pages.into_iter().map(|item| item.page).collect())
}

fn build_claims_from_documents(documents: &[ContentKnowledgeDocument]) -> Vec<KnowledgeClaim> {
    documents
        .iter()
        .map(|document| {
            let statement = document
                .summary
                .clone()
                .unwrap_or_else(|| document.raw_text.clone());
            let claim_type = claim_type_for_document_id(&document.document_id);
            let time_scope = match claim_type {
                KnowledgeClaimType::Preference | KnowledgeClaimType::Identity => {
                    KnowledgeClaimTimeScope::Stable
                }
                KnowledgeClaimType::Event | KnowledgeClaimType::Thread => {
                    KnowledgeClaimTimeScope::Recent
                }
                _ => KnowledgeClaimTimeScope::Current,
            };
            let status = if document.memory_feedback.is_deleted {
                KnowledgeClaimStatus::Dismissed
            } else if document.memory_feedback.marked_inaccurate {
                KnowledgeClaimStatus::Disputed
            } else {
                KnowledgeClaimStatus::Active
            };
            let answer_allowed = document.memory_feedback.use_for_ask_ai
                && !document.memory_feedback.is_deleted
                && !document.memory_feedback.marked_inaccurate;

            KnowledgeClaim {
                claim_id: format!("claim:{}", document.document_id),
                subject_id: "user:self".to_string(),
                claim_type,
                facet_key: facet_key_for_document_id(&document.document_id),
                statement: statement.trim().to_string(),
                normalized_value: document.summary.clone(),
                time_scope,
                valid_from_ms: None,
                valid_until_ms: None,
                confidence: document.quality_score,
                source_ref_ids: source_refs_for_document(document),
                source_count: document
                    .memory_display
                    .as_ref()
                    .map(|value| value.source_count)
                    .unwrap_or(1),
                conflict_with_claim_ids: Vec::new(),
                status,
                human_confirmed: document.memory_feedback.status.is_some(),
                human_corrected: document.memory_feedback.corrected_title.is_some()
                    || document.memory_feedback.corrected_summary.is_some(),
                answer_allowed,
                created_at_ms: document.created_at_ms,
                updated_at_ms: document.updated_at_ms,
            }
        })
        .collect()
}

fn source_refs_for_document(document: &ContentKnowledgeDocument) -> Vec<String> {
    let mut refs = BTreeSet::from([document.document_id.clone()]);
    if let Some(message_id) = document.anchors.message_id.as_ref() {
        refs.insert(format!("message:{message_id}"));
    }
    if let Some(attachment_sha256) = document.anchors.attachment_sha256.as_ref() {
        refs.insert(format!("attachment:{attachment_sha256}"));
    }
    refs.into_iter().collect()
}

fn compile_pages_from_claims(
    documents: &[ContentKnowledgeDocument],
    claims: &[KnowledgeClaim],
) -> Vec<CompiledKnowledgePageRecord> {
    let mut by_page_type = BTreeMap::<KnowledgePageType, Vec<usize>>::new();
    for (index, document) in documents.iter().enumerate() {
        if let Some(page_type) = page_type_for_document_id(&document.document_id) {
            by_page_type.entry(page_type).or_default().push(index);
        }
    }

    by_page_type
        .into_iter()
        .map(|(page_type, indexes)| {
            let page_id = page_id_for_type(page_type);
            let title = page_title(page_type);
            let mut body_lines = Vec::<String>::new();
            let mut summary_lines = Vec::<String>::new();
            let mut primary_evidence_ids = Vec::<String>::new();
            let mut source_document_ids = Vec::<String>::new();
            let mut latest_updated_at = 0_i64;
            let mut source_count = 0_i64;
            let mut confidence_total = 0.0_f64;
            let mut claim_ids = Vec::<String>::new();

            for index in indexes {
                let document = &documents[index];
                let document_title = document
                    .title
                    .as_deref()
                    .unwrap_or_else(|| fallback_title_for_document(document));
                let document_summary = document
                    .summary
                    .as_deref()
                    .unwrap_or(document.raw_text.as_str())
                    .trim();
                body_lines.push(format!("- {document_title}: {document_summary}"));
                summary_lines.push(document_summary.to_string());
                primary_evidence_ids.push(document.document_id.clone());
                source_document_ids.push(document.document_id.clone());
                latest_updated_at = latest_updated_at.max(document.updated_at_ms);
                source_count += document
                    .memory_display
                    .as_ref()
                    .map(|value| value.source_count)
                    .unwrap_or(1)
                    .max(1);
                confidence_total += document.quality_score;
                claim_ids.push(format!("claim:{}", document.document_id));
            }

            let related_page_ids = related_page_ids_for_type(page_type);
            let tags = tags_for_page_type(page_type);
            let mut page = KnowledgePage::new(page_id.clone(), page_type, title, latest_updated_at);
            page.current_summary = summarize_lines(&summary_lines);
            page.current_body = body_lines.join("\n");
            page.updated_at_ms = latest_updated_at;
            page.source_count = source_count.max(1);
            page.conflict_count = count_conflicts_for_page(&page_id, claims);
            page.confidence_level = if source_document_ids.is_empty() {
                0.0
            } else {
                confidence_total / source_document_ids.len() as f64
            };
            page.tags = tags;
            page.primary_evidence_ids = dedup(primary_evidence_ids);
            page.related_page_ids = related_page_ids;
            if page.current_body.is_empty() {
                page.current_body = page.current_summary.clone();
            }
            CompiledKnowledgePageRecord {
                page,
                source_document_ids: dedup(source_document_ids),
                claim_ids: dedup(claim_ids),
            }
        })
        .collect()
}

fn summarize_lines(lines: &[String]) -> String {
    let trimmed = lines
        .iter()
        .map(|line| line.trim())
        .filter(|line| !line.is_empty())
        .take(3)
        .collect::<Vec<_>>();
    trimmed.join(" ")
}

fn count_conflicts_for_page(page_id: &str, claims: &[KnowledgeClaim]) -> i64 {
    let page_type = page_type_for_page_id(page_id);
    let mut by_facet = BTreeMap::<String, BTreeSet<String>>::new();
    for claim in claims {
        let Some(claim_page_type) = page_type_for_claim(claim) else {
            continue;
        };
        if Some(claim_page_type) != page_type {
            continue;
        }
        by_facet
            .entry(claim.facet_key.clone())
            .or_default()
            .insert(claim.statement.clone());
    }
    by_facet.values().filter(|values| values.len() > 1).count() as i64
}

fn page_type_for_claim(claim: &KnowledgeClaim) -> Option<KnowledgePageType> {
    match claim.claim_type {
        KnowledgeClaimType::Preference => Some(KnowledgePageType::Preferences),
        KnowledgeClaimType::Identity => Some(KnowledgePageType::AboutMe),
        KnowledgeClaimType::Focus | KnowledgeClaimType::Thread => {
            Some(KnowledgePageType::CurrentFocus)
        }
        KnowledgeClaimType::Event => Some(KnowledgePageType::RecentEvents),
        KnowledgeClaimType::Relationship => Some(KnowledgePageType::People),
        KnowledgeClaimType::Topic => Some(KnowledgePageType::Topics),
        KnowledgeClaimType::Question => Some(KnowledgePageType::OpenQuestions),
    }
}

fn claim_type_for_document_id(document_id: &str) -> KnowledgeClaimType {
    if document_id.starts_with("generated:preference:") {
        KnowledgeClaimType::Preference
    } else if document_id.starts_with("generated:profile:") {
        KnowledgeClaimType::Identity
    } else if document_id.starts_with("generated:event:") {
        KnowledgeClaimType::Event
    } else if document_id.starts_with("generated:pattern:active-task-focus") {
        KnowledgeClaimType::Focus
    } else if document_id.starts_with("generated:pattern:") {
        KnowledgeClaimType::Topic
    } else {
        KnowledgeClaimType::Topic
    }
}

fn facet_key_for_document_id(document_id: &str) -> String {
    document_id
        .split(':')
        .next_back()
        .unwrap_or(document_id)
        .trim()
        .replace('-', "_")
}

fn page_type_for_document_id(document_id: &str) -> Option<KnowledgePageType> {
    if document_id.starts_with("generated:preference:") {
        Some(KnowledgePageType::Preferences)
    } else if document_id.starts_with("generated:profile:") {
        Some(KnowledgePageType::AboutMe)
    } else if document_id.starts_with("generated:event:") {
        Some(KnowledgePageType::RecentEvents)
    } else if document_id.starts_with("generated:pattern:active-task-focus") {
        Some(KnowledgePageType::CurrentFocus)
    } else if document_id.starts_with("generated:pattern:") {
        Some(KnowledgePageType::Topics)
    } else {
        None
    }
}

fn page_type_for_page_id(page_id: &str) -> Option<KnowledgePageType> {
    match page_id {
        "page:about-me" => Some(KnowledgePageType::AboutMe),
        "page:preferences" => Some(KnowledgePageType::Preferences),
        "page:current-focus" => Some(KnowledgePageType::CurrentFocus),
        "page:active-threads" => Some(KnowledgePageType::ActiveThreads),
        "page:recent-events" => Some(KnowledgePageType::RecentEvents),
        "page:people" => Some(KnowledgePageType::People),
        "page:topics" => Some(KnowledgePageType::Topics),
        "page:open-questions" => Some(KnowledgePageType::OpenQuestions),
        _ => None,
    }
}

fn page_id_for_type(page_type: KnowledgePageType) -> String {
    match page_type {
        KnowledgePageType::AboutMe => "page:about-me",
        KnowledgePageType::Preferences => "page:preferences",
        KnowledgePageType::CurrentFocus => "page:current-focus",
        KnowledgePageType::ActiveThreads => "page:active-threads",
        KnowledgePageType::RecentEvents => "page:recent-events",
        KnowledgePageType::People => "page:people",
        KnowledgePageType::Topics => "page:topics",
        KnowledgePageType::OpenQuestions => "page:open-questions",
    }
    .to_string()
}

fn page_title(page_type: KnowledgePageType) -> &'static str {
    match page_type {
        KnowledgePageType::AboutMe => "About Me",
        KnowledgePageType::Preferences => "Preferences",
        KnowledgePageType::CurrentFocus => "Current Focus",
        KnowledgePageType::ActiveThreads => "Active Threads",
        KnowledgePageType::RecentEvents => "Recent Events",
        KnowledgePageType::People => "People",
        KnowledgePageType::Topics => "Topics",
        KnowledgePageType::OpenQuestions => "Open Questions",
    }
}

fn related_page_ids_for_type(page_type: KnowledgePageType) -> Vec<String> {
    match page_type {
        KnowledgePageType::Preferences => vec!["page:about-me".to_string()],
        KnowledgePageType::AboutMe => vec!["page:preferences".to_string()],
        KnowledgePageType::CurrentFocus => vec!["page:recent-events".to_string()],
        KnowledgePageType::RecentEvents => vec!["page:current-focus".to_string()],
        KnowledgePageType::Topics => vec!["page:current-focus".to_string()],
        _ => Vec::new(),
    }
}

fn tags_for_page_type(page_type: KnowledgePageType) -> Vec<String> {
    match page_type {
        KnowledgePageType::AboutMe => vec!["identity".to_string()],
        KnowledgePageType::Preferences => vec!["preferences".to_string()],
        KnowledgePageType::CurrentFocus => vec!["focus".to_string()],
        KnowledgePageType::ActiveThreads => vec!["threads".to_string()],
        KnowledgePageType::RecentEvents => vec!["recent".to_string()],
        KnowledgePageType::People => vec!["people".to_string()],
        KnowledgePageType::Topics => vec!["topics".to_string()],
        KnowledgePageType::OpenQuestions => vec!["questions".to_string()],
    }
}

fn fallback_title_for_document(document: &ContentKnowledgeDocument) -> &str {
    document
        .summary
        .as_deref()
        .or(document.title.as_deref())
        .unwrap_or(document.document_id.as_str())
}

fn dedup(values: Vec<String>) -> Vec<String> {
    let mut seen = BTreeSet::<String>::new();
    let mut out = Vec::<String>::new();
    for value in values {
        if seen.insert(value.clone()) {
            out.push(value);
        }
    }
    out
}

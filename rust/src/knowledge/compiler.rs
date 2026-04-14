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

#[derive(Clone, Debug)]
struct PageSeed {
    page_id: String,
    page_type: KnowledgePageType,
    title: String,
    related_page_ids: Vec<String>,
    tags: Vec<String>,
}

#[derive(Default)]
struct ClaimCompilationIndex {
    by_page_id: BTreeMap<String, Vec<usize>>,
    by_page_and_document_id: BTreeMap<String, BTreeMap<String, Vec<usize>>>,
}

pub fn refresh_knowledge_pages(conn: &Connection, key: &[u8; 32]) -> Result<Vec<KnowledgePage>> {
    let generated_documents = load_all_generated_documents(conn, key)?;
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

pub fn refresh_knowledge_pages_if_required(conn: &Connection, key: &[u8; 32]) -> Result<bool> {
    if !crate::db::knowledge_pages_refresh_required(conn)? {
        return Ok(false);
    }
    let _ = refresh_knowledge_pages(conn, key)?;
    crate::db::mark_knowledge_pages_refreshed(conn, crate::knowledge::usage::now_ms())?;
    Ok(true)
}

fn load_all_generated_documents(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Vec<ContentKnowledgeDocument>> {
    const PAGE_SIZE: usize = 256;
    let mut documents = Vec::<ContentKnowledgeDocument>::new();
    let mut offset = 0usize;
    loop {
        let page = crate::knowledge::list_knowledge_documents_by_origin(
            conn,
            key,
            KnowledgeOriginType::Generated,
            PAGE_SIZE,
            offset,
        )?;
        let fetched = page.len();
        documents.extend(page);
        if fetched < PAGE_SIZE {
            break;
        }
        offset += fetched;
    }
    Ok(documents)
}

fn build_claims_from_documents(documents: &[ContentKnowledgeDocument]) -> Vec<KnowledgeClaim> {
    documents
        .iter()
        .flat_map(|document| {
            let statement = document
                .summary
                .clone()
                .unwrap_or_else(|| document.raw_text.clone());
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
            claim_types_for_document_id(&document.document_id)
                .into_iter()
                .map(move |claim_type| {
                    let time_scope = match claim_type {
                        KnowledgeClaimType::Preference | KnowledgeClaimType::Identity => {
                            KnowledgeClaimTimeScope::Stable
                        }
                        KnowledgeClaimType::Event | KnowledgeClaimType::Thread => {
                            KnowledgeClaimTimeScope::Recent
                        }
                        _ => KnowledgeClaimTimeScope::Current,
                    };

                    KnowledgeClaim {
                        claim_id: claim_id_for_document(&document.document_id, claim_type),
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

fn document_source_refs(source_ref_ids: &[String]) -> Vec<String> {
    source_ref_ids
        .iter()
        .filter(|source_ref| {
            !source_ref.starts_with("message:") && !source_ref.starts_with("attachment:")
        })
        .cloned()
        .collect()
}

fn compile_pages_from_claims(
    documents: &[ContentKnowledgeDocument],
    claims: &[KnowledgeClaim],
) -> Vec<CompiledKnowledgePageRecord> {
    let claim_index = build_claim_compilation_index(claims);
    let mut by_page_id = BTreeMap::<String, (PageSeed, Vec<usize>)>::new();
    for (index, document) in documents.iter().enumerate() {
        for seed in page_seeds_for_document(document) {
            by_page_id
                .entry(seed.page_id.clone())
                .or_insert_with(|| (seed.clone(), Vec::new()))
                .1
                .push(index);
        }
    }

    let mut compiled = by_page_id
        .into_iter()
        .map(|(_, (seed, indexes))| {
            let mut body_lines = Vec::<String>::new();
            let mut summary_lines = Vec::<String>::new();
            let mut primary_evidence_ids = Vec::<String>::new();
            let mut source_document_ids = Vec::<String>::new();
            let mut contributing_document_count = 0_usize;
            let mut latest_updated_at = 0_i64;
            let mut source_count = 0_i64;
            let mut confidence_total = 0.0_f64;
            let mut claim_ids = Vec::<String>::new();

            for index in indexes {
                let document = &documents[index];
                let page_claims = claim_index
                    .by_page_and_document_id
                    .get(&seed.page_id)
                    .and_then(|by_document| by_document.get(&document.document_id))
                    .map(|claim_indexes| {
                        claim_indexes
                            .iter()
                            .map(|index| &claims[*index])
                            .collect::<Vec<_>>()
                    })
                    .unwrap_or_default();
                if page_claims.is_empty() {
                    continue;
                }
                let current_page_claims = page_claims
                    .into_iter()
                    .filter(|claim| {
                        claim.answer_allowed
                            && matches!(
                                claim.status,
                                KnowledgeClaimStatus::Active | KnowledgeClaimStatus::Supporting
                            )
                    })
                    .collect::<Vec<_>>();
                if current_page_claims.is_empty() {
                    continue;
                }
                let document_title = document
                    .title
                    .as_deref()
                    .unwrap_or_else(|| fallback_title_for_document(document));
                let document_summary = document
                    .summary
                    .as_deref()
                    .unwrap_or(document.raw_text.as_str())
                    .trim();
                if seed.page_type == KnowledgePageType::ActiveThreads
                    && document.document_id == "generated:pattern:active-task-focus"
                {
                    body_lines.push(document.raw_text.trim().to_string());
                } else {
                    body_lines.push(format!("- {document_title}: {document_summary}"));
                }
                summary_lines.push(document_summary.to_string());
                primary_evidence_ids.push(document.document_id.clone());
                latest_updated_at = latest_updated_at.max(document.updated_at_ms);
                source_count += document
                    .memory_display
                    .as_ref()
                    .map(|value| value.source_count)
                    .unwrap_or(1)
                    .max(1);
                contributing_document_count += 1;
                confidence_total += document.quality_score;
                source_document_ids.push(document.document_id.clone());
                claim_ids.extend(
                    current_page_claims
                        .into_iter()
                        .map(|claim| claim.claim_id.clone()),
                );
            }
            if summary_lines.is_empty() && body_lines.is_empty() {
                return None;
            }

            let mut page = KnowledgePage::new(
                seed.page_id.clone(),
                seed.page_type,
                seed.title.clone(),
                latest_updated_at,
            );
            page.current_summary = summarize_lines(&summary_lines);
            page.current_body = body_lines.join("\n");
            page.updated_at_ms = latest_updated_at;
            page.source_count = source_count.max(1);
            page.conflict_count =
                count_conflicts_for_page(claims, claim_index.by_page_id.get(&seed.page_id));
            page.confidence_level = if contributing_document_count == 0 {
                0.0
            } else {
                confidence_total / contributing_document_count as f64
            };
            page.tags = seed.tags.clone();
            page.primary_evidence_ids = dedup(primary_evidence_ids);
            page.related_page_ids = seed.related_page_ids.clone();
            if page.current_body.is_empty() {
                page.current_body = page.current_summary.clone();
            }
            Some(CompiledKnowledgePageRecord {
                page,
                source_document_ids: dedup(source_document_ids),
                claim_ids: dedup(claim_ids),
            })
        })
        .flatten()
        .collect::<Vec<_>>();
    compiled.extend(compile_open_question_pages(claims));
    compiled
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

fn count_conflicts_for_page(claims: &[KnowledgeClaim], claim_indexes: Option<&Vec<usize>>) -> i64 {
    let mut by_facet = BTreeMap::<String, BTreeSet<String>>::new();
    let Some(claim_indexes) = claim_indexes else {
        return 0;
    };
    for claim in claim_indexes.iter().map(|index| &claims[*index]) {
        if claim.status == KnowledgeClaimStatus::Dismissed || !claim.answer_allowed {
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
        KnowledgeClaimType::Focus => Some(KnowledgePageType::CurrentFocus),
        KnowledgeClaimType::Thread => Some(KnowledgePageType::ActiveThreads),
        KnowledgeClaimType::Event => Some(KnowledgePageType::RecentEvents),
        KnowledgeClaimType::Relationship => Some(KnowledgePageType::People),
        KnowledgeClaimType::Topic => Some(KnowledgePageType::Topics),
        KnowledgeClaimType::Question => Some(KnowledgePageType::OpenQuestions),
    }
}

fn claim_types_for_document_id(document_id: &str) -> Vec<KnowledgeClaimType> {
    if document_id.starts_with("generated:preference:") {
        vec![KnowledgeClaimType::Preference]
    } else if document_id.starts_with("generated:profile:person-") {
        vec![KnowledgeClaimType::Relationship]
    } else if document_id.starts_with("generated:profile:") {
        vec![KnowledgeClaimType::Identity]
    } else if document_id.starts_with("generated:event:") {
        vec![KnowledgeClaimType::Event]
    } else if document_id.starts_with("generated:pattern:active-task-focus") {
        vec![KnowledgeClaimType::Focus, KnowledgeClaimType::Thread]
    } else if document_id.starts_with("generated:pattern:") {
        vec![KnowledgeClaimType::Topic]
    } else {
        vec![KnowledgeClaimType::Topic]
    }
}

fn claim_id_for_document(document_id: &str, claim_type: KnowledgeClaimType) -> String {
    format!("claim:{}:{document_id}", claim_type_label(claim_type))
}

fn claim_type_label(claim_type: KnowledgeClaimType) -> &'static str {
    match claim_type {
        KnowledgeClaimType::Identity => "identity",
        KnowledgeClaimType::Preference => "preference",
        KnowledgeClaimType::Focus => "focus",
        KnowledgeClaimType::Thread => "thread",
        KnowledgeClaimType::Event => "event",
        KnowledgeClaimType::Relationship => "relationship",
        KnowledgeClaimType::Topic => "topic",
        KnowledgeClaimType::Question => "question",
    }
}

pub(crate) fn facet_key_for_document_id(document_id: &str) -> String {
    if document_id.starts_with("generated:profile:person-") {
        return people_facet_key_for_document_id(document_id);
    }
    document_id
        .split(':')
        .next_back()
        .unwrap_or(document_id)
        .trim()
        .replace('-', "_")
}

fn people_facet_key_for_document_id(document_id: &str) -> String {
    document_id
        .strip_prefix("generated:profile:person-")
        .unwrap_or(document_id)
        .trim()
        .replace('-', "_")
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

pub(crate) fn primary_page_ids_for_generated_document(document_id: &str) -> Vec<String> {
    if document_id.starts_with("generated:preference:") {
        vec![page_id_for_type(KnowledgePageType::Preferences)]
    } else if document_id.starts_with("generated:profile:person-") {
        vec![page_id_for_type_with_facet(
            KnowledgePageType::People,
            &people_facet_key_for_document_id(document_id),
        )]
    } else if document_id.starts_with("generated:profile:") {
        vec![page_id_for_type(KnowledgePageType::AboutMe)]
    } else if document_id.starts_with("generated:event:") {
        vec![page_id_for_type(KnowledgePageType::RecentEvents)]
    } else if document_id.starts_with("generated:pattern:active-task-focus") {
        vec![
            page_id_for_type(KnowledgePageType::CurrentFocus),
            page_id_for_type(KnowledgePageType::ActiveThreads),
        ]
    } else if document_id.starts_with("generated:pattern:") {
        vec![page_id_for_type_with_facet(
            KnowledgePageType::Topics,
            &facet_key_for_document_id(document_id),
        )]
    } else {
        Vec::new()
    }
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

fn page_seeds_for_document(document: &ContentKnowledgeDocument) -> Vec<PageSeed> {
    if document.document_id.starts_with("generated:preference:") {
        vec![singleton_page_seed(KnowledgePageType::Preferences)]
    } else if document
        .document_id
        .starts_with("generated:profile:person-")
    {
        let facet_key = people_facet_key_for_document_id(&document.document_id);
        vec![faceted_page_seed(
            KnowledgePageType::People,
            &facet_key,
            page_title_for_facet(
                document.title.as_deref(),
                fallback_title_for_document(document),
                "Person",
                &facet_key,
            ),
        )]
    } else if document.document_id.starts_with("generated:profile:") {
        vec![singleton_page_seed(KnowledgePageType::AboutMe)]
    } else if document.document_id.starts_with("generated:event:") {
        vec![singleton_page_seed(KnowledgePageType::RecentEvents)]
    } else if document
        .document_id
        .starts_with("generated:pattern:active-task-focus")
    {
        vec![
            singleton_page_seed(KnowledgePageType::CurrentFocus),
            singleton_page_seed(KnowledgePageType::ActiveThreads),
        ]
    } else if document.document_id.starts_with("generated:pattern:") {
        let facet_key = facet_key_for_document_id(&document.document_id);
        vec![faceted_page_seed(
            KnowledgePageType::Topics,
            &facet_key,
            page_title_for_facet(
                document.title.as_deref(),
                fallback_title_for_document(document),
                "Topic",
                &facet_key,
            ),
        )]
    } else {
        Vec::new()
    }
}

fn singleton_page_seed(page_type: KnowledgePageType) -> PageSeed {
    PageSeed {
        page_id: page_id_for_type(page_type),
        page_type,
        title: page_title(page_type).to_string(),
        related_page_ids: related_page_ids_for_type(page_type),
        tags: tags_for_page_type(page_type),
    }
}

fn faceted_page_seed(page_type: KnowledgePageType, facet_key: &str, title: String) -> PageSeed {
    PageSeed {
        page_id: page_id_for_type_with_facet(page_type, facet_key),
        page_type,
        title,
        related_page_ids: related_page_ids_for_type(page_type),
        tags: tags_for_page_type(page_type),
    }
}

fn page_id_for_type_with_facet(page_type: KnowledgePageType, facet_key: &str) -> String {
    format!("{}:{facet_key}", page_id_for_type(page_type))
}

fn build_claim_compilation_index(claims: &[KnowledgeClaim]) -> ClaimCompilationIndex {
    let mut index = ClaimCompilationIndex::default();
    for (claim_index, claim) in claims.iter().enumerate() {
        let Some(page_id) = compiled_page_id_for_claim(claim) else {
            continue;
        };
        index
            .by_page_id
            .entry(page_id.clone())
            .or_default()
            .push(claim_index);
        for document_id in dedup(document_source_refs(&claim.source_ref_ids)) {
            index
                .by_page_and_document_id
                .entry(page_id.clone())
                .or_default()
                .entry(document_id)
                .or_default()
                .push(claim_index);
        }
    }
    index
}

fn compiled_page_id_for_claim(claim: &KnowledgeClaim) -> Option<String> {
    let page_type = page_type_for_claim(claim)?;
    Some(match page_type {
        KnowledgePageType::People | KnowledgePageType::Topics => {
            page_id_for_type_with_facet(page_type, &claim.facet_key)
        }
        KnowledgePageType::OpenQuestions => open_question_page_id_for_claim(claim),
        _ => page_id_for_type(page_type),
    })
}

fn compile_open_question_pages(claims: &[KnowledgeClaim]) -> Vec<CompiledKnowledgePageRecord> {
    let mut by_page_id = BTreeMap::<String, Vec<&KnowledgeClaim>>::new();
    for claim in claims
        .iter()
        .filter(|claim| claim.status == KnowledgeClaimStatus::Disputed)
    {
        by_page_id
            .entry(open_question_page_id_for_claim(claim))
            .or_default()
            .push(claim);
    }

    by_page_id
        .into_iter()
        .map(|(page_id, grouped_claims)| {
            let latest_updated_at = grouped_claims
                .iter()
                .map(|claim| claim.updated_at_ms)
                .max()
                .unwrap_or_default();
            let summary_lines = grouped_claims
                .iter()
                .map(|claim| claim.statement.trim().to_string())
                .collect::<Vec<_>>();
            let claim_ids = grouped_claims
                .iter()
                .map(|claim| claim.claim_id.clone())
                .collect::<Vec<_>>();
            let source_document_ids = grouped_claims
                .iter()
                .flat_map(|claim| document_source_refs(&claim.source_ref_ids))
                .collect::<Vec<_>>();
            let primary_evidence_ids = grouped_claims
                .iter()
                .flat_map(|claim| document_source_refs(&claim.source_ref_ids))
                .collect::<Vec<_>>();
            let confidence_level = grouped_claims
                .iter()
                .map(|claim| claim.confidence)
                .sum::<f64>()
                / grouped_claims.len().max(1) as f64;
            let mut page = KnowledgePage::new(
                page_id.clone(),
                KnowledgePageType::OpenQuestions,
                open_question_title_for_claim(grouped_claims[0]),
                latest_updated_at,
            );
            page.current_summary = summarize_lines(&summary_lines);
            page.current_body = summary_lines
                .iter()
                .map(|line| format!("- {line}"))
                .collect::<Vec<_>>()
                .join("\n");
            page.state = crate::knowledge::KnowledgePageState::NeedsReview;
            page.answer_policy = crate::knowledge::state_default_answer_policy(page.state);
            page.updated_at_ms = latest_updated_at;
            page.source_count = grouped_claims
                .iter()
                .map(|claim| claim.source_count.max(1))
                .sum::<i64>()
                .max(1);
            page.conflict_count = grouped_claims.len() as i64;
            page.confidence_level = confidence_level;
            page.tags = tags_for_page_type(KnowledgePageType::OpenQuestions);
            page.primary_evidence_ids = dedup(primary_evidence_ids);
            page.related_page_ids = related_page_ids_for_open_question(grouped_claims[0]);
            CompiledKnowledgePageRecord {
                page,
                source_document_ids: dedup(source_document_ids),
                claim_ids: dedup(claim_ids),
            }
        })
        .collect()
}

fn open_question_page_id_for_claim(claim: &KnowledgeClaim) -> String {
    format!(
        "page:open-questions:{}:{}",
        claim_type_label(claim.claim_type),
        claim.facet_key
    )
}

fn open_question_title_for_claim(claim: &KnowledgeClaim) -> String {
    page_title_for_facet(None, &claim.statement, "Open Question", &claim.facet_key)
}

fn related_page_ids_for_open_question(claim: &KnowledgeClaim) -> Vec<String> {
    match claim.claim_type {
        KnowledgeClaimType::Preference => vec![page_id_for_type(KnowledgePageType::Preferences)],
        KnowledgeClaimType::Identity => vec![page_id_for_type(KnowledgePageType::AboutMe)],
        KnowledgeClaimType::Focus => vec![page_id_for_type(KnowledgePageType::CurrentFocus)],
        KnowledgeClaimType::Thread => vec![page_id_for_type(KnowledgePageType::ActiveThreads)],
        KnowledgeClaimType::Event => vec![page_id_for_type(KnowledgePageType::RecentEvents)],
        KnowledgeClaimType::Relationship => {
            vec![page_id_for_type_with_facet(
                KnowledgePageType::People,
                &claim.facet_key,
            )]
        }
        KnowledgeClaimType::Topic => {
            vec![page_id_for_type_with_facet(
                KnowledgePageType::Topics,
                &claim.facet_key,
            )]
        }
        KnowledgeClaimType::Question => Vec::new(),
    }
}

fn page_title_for_facet(
    explicit_title: Option<&str>,
    fallback_title: &str,
    label_prefix: &str,
    facet_key: &str,
) -> String {
    let explicit_title = explicit_title
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(fallback_title)
        .trim();
    if !explicit_title.is_empty() && explicit_title != fallback_title {
        return explicit_title.to_string();
    }
    let humanized = humanize_facet_key(facet_key);
    if humanized.is_empty() {
        label_prefix.to_string()
    } else {
        format!("{label_prefix} {humanized}")
    }
}

fn humanize_facet_key(facet_key: &str) -> String {
    facet_key
        .split('_')
        .filter(|part| !part.trim().is_empty())
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                Some(first) => {
                    let mut word = first.to_uppercase().collect::<String>();
                    word.push_str(chars.as_str());
                    word
                }
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
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

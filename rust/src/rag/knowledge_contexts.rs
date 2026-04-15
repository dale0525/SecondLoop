use anyhow::Result;
use rusqlite::Connection;
use std::cmp::Ordering;

const FORCED_GENERATED_CONTEXT_SCORE: f64 = 0.0;

use crate::knowledge;
use crate::message_citations::append_message_citation_if_missing;

use super::Focus;

#[derive(Clone, Debug, PartialEq)]
pub(super) struct KnowledgeRenderedContextEntry {
    pub(super) block: knowledge::KnowledgeContextBlock,
    pub(super) rendered_text: String,
}

fn lexical_page_match_score(question: &str, haystack: &str) -> usize {
    let question = question.to_lowercase();
    let haystack = haystack.to_lowercase();
    let word_score = question
        .split(|ch: char| !ch.is_alphanumeric() && !('\u{4E00}'..='\u{9FFF}').contains(&ch))
        .map(str::trim)
        .filter(|token| token.chars().count() >= 2 && !token.chars().all(is_cjk_character))
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .filter(|token| haystack.contains(*token))
        .count();
    let cjk_score = cjk_query_ngrams(&question)
        .into_iter()
        .filter(|token| haystack.contains(token))
        .count();
    word_score + cjk_score
}

fn is_cjk_character(ch: char) -> bool {
    ('\u{4E00}'..='\u{9FFF}').contains(&ch)
}

fn cjk_query_ngrams(text: &str) -> std::collections::BTreeSet<String> {
    let mut out = std::collections::BTreeSet::<String>::new();
    let mut current = Vec::<char>::new();
    for ch in text.chars() {
        if is_cjk_character(ch) {
            current.push(ch);
            continue;
        }
        append_cjk_ngrams(&mut out, &current);
        current.clear();
    }
    append_cjk_ngrams(&mut out, &current);
    out
}

fn append_cjk_ngrams(out: &mut std::collections::BTreeSet<String>, chars: &[char]) {
    if chars.len() == 1 {
        out.insert(chars[0].to_string());
        return;
    }
    if chars.len() < 2 {
        return;
    }
    for gram_len in 2..=3 {
        if chars.len() < gram_len {
            continue;
        }
        for start in 0..=chars.len() - gram_len {
            out.insert(chars[start..start + gram_len].iter().collect::<String>());
        }
    }
}

fn planning_context_group(block: &knowledge::KnowledgeContextBlock) -> u8 {
    if block.document_id.starts_with("generated:session-digest:") {
        0
    } else if !block.document_id.starts_with("page:") {
        1
    } else {
        2
    }
}

fn planning_page_priority(document_id: &str) -> u8 {
    match document_id {
        "page:current-focus" => 0,
        "page:active-threads" => 1,
        "page:recent-events" => 2,
        "page:preferences" => 3,
        "page:about-me" => 4,
        _ => 5,
    }
}

fn compare_block_scores(left: f64, right: f64) -> Ordering {
    right.partial_cmp(&left).unwrap_or(Ordering::Equal)
}

fn sort_planning_contexts(blocks: &mut [knowledge::KnowledgeContextBlock]) {
    blocks.sort_by(|left, right| {
        planning_context_group(left)
            .cmp(&planning_context_group(right))
            .then_with(|| compare_block_scores(left.score, right.score))
            .then_with(|| {
                if left.document_id.starts_with("page:") || right.document_id.starts_with("page:") {
                    planning_page_priority(&left.document_id)
                        .cmp(&planning_page_priority(&right.document_id))
                } else {
                    Ordering::Equal
                }
            })
            .then_with(|| left.document_id.cmp(&right.document_id))
    });
}

pub(super) fn should_exclude_generated_document_for_page_policies(
    document_id: &str,
    excluded_page_ids: &std::collections::HashSet<String>,
) -> bool {
    let related_page_ids =
        knowledge::compiler::primary_page_ids_for_generated_document(document_id);
    !related_page_ids.is_empty()
        && related_page_ids
            .iter()
            .all(|page_id| excluded_page_ids.contains(page_id))
}

fn page_context_allowed(page: &knowledge::KnowledgePage) -> bool {
    page.answer_policy.default_allowed || page.answer_policy.requires_temporal_framing
}

fn page_type_allowed_for_conversation_scope(
    page_type: knowledge::KnowledgePageType,
    conversation_scope: Option<&str>,
) -> bool {
    if conversation_scope.is_none() {
        return true;
    }
    matches!(
        page_type,
        knowledge::KnowledgePageType::AboutMe | knowledge::KnowledgePageType::Preferences
    )
}

fn page_context_allowed_in_scope(
    page: &knowledge::KnowledgePage,
    conversation_scope: Option<&str>,
) -> bool {
    page_context_allowed(page)
        && page_type_allowed_for_conversation_scope(page.page_type, conversation_scope)
}

fn render_page_context_block(
    page: &knowledge::KnowledgePage,
    score: f64,
) -> knowledge::KnowledgeContextBlock {
    let mut rendered = format!(
        "page_id={}\npage_state={}\n[knowledge layer=wiki_page source=wiki_page role=summary]\n{}\n{}",
        page.page_id,
        page.user_state_label(),
        page.current_summary,
        page.current_body,
    );
    if page.answer_policy.requires_temporal_framing {
        rendered = format!(
            "temporal_framing=required\n{}\n{}",
            rendered, "This page may be outdated and should be framed with time context."
        );
    }
    knowledge::KnowledgeContextBlock {
        document_id: page.page_id.clone(),
        unit_id: None,
        unit_kind: None,
        source_kind: knowledge::KnowledgeSourceKind::Summary,
        role: knowledge::KnowledgeRole::Summary,
        anchors: knowledge::KnowledgeAnchorSet::default(),
        score,
        rendered_text: rendered,
    }
}

fn build_generated_planning_fallback_block(
    document: knowledge::ContentKnowledgeDocument,
) -> Option<knowledge::KnowledgeContextBlock> {
    let body = if document.raw_text.trim().is_empty() {
        document.normalized_text.trim()
    } else {
        document.raw_text.trim()
    };
    if body.is_empty() {
        return None;
    }
    Some(knowledge::KnowledgeContextBlock {
        document_id: document.document_id.clone(),
        unit_id: None,
        unit_kind: None,
        source_kind: document.source_kind,
        role: document.role,
        anchors: document.anchors.clone(),
        score: FORCED_GENERATED_CONTEXT_SCORE,
        rendered_text: format!(
            "{}\n[knowledge layer=document source=summary role=summary]\n{}",
            if let Some(conversation_id) = document.anchors.conversation_id.as_deref() {
                format!("conversation_id={conversation_id}")
            } else {
                "generated_memory=global".to_string()
            },
            body,
        ),
    })
}

fn collect_matching_page_context_candidates<'a, I, F>(
    question: &str,
    is_planning_query: bool,
    summaries: I,
    load_page_body: &mut F,
) -> Vec<(String, usize)>
where
    I: IntoIterator<Item = &'a (knowledge::KnowledgePageSummary, usize)>,
    F: FnMut(&str) -> Option<String>,
{
    let mut candidates = Vec::<(String, usize)>::new();
    for (summary, prefilter_score) in summaries {
        let Some(page_body) = load_page_body(&summary.page_id) else {
            continue;
        };
        let lexical_score = lexical_page_match_score(
            question,
            &format!(
                "{}\n{}\n{}",
                summary.title, summary.current_summary, page_body
            ),
        );
        if !is_planning_query && lexical_score == 0 {
            continue;
        }
        candidates.push((summary.page_id.clone(), lexical_score.max(*prefilter_score)));
    }
    candidates
}

pub(super) fn collect_matching_page_context_blocks<F, G>(
    question: &str,
    top_k: usize,
    is_planning_query: bool,
    candidate_summaries: Vec<(knowledge::KnowledgePageSummary, usize)>,
    mut load_page_body: F,
    mut load_page: G,
) -> Vec<knowledge::KnowledgeContextBlock>
where
    F: FnMut(&str) -> Option<String>,
    G: FnMut(&str) -> Option<knowledge::KnowledgePage>,
{
    let mut candidates = collect_matching_page_context_candidates(
        question,
        is_planning_query,
        candidate_summaries.iter(),
        &mut load_page_body,
    );
    candidates.sort_by(|left, right| right.1.cmp(&left.1));
    candidates
        .into_iter()
        .take(top_k.max(1))
        .filter_map(|(page_id, score)| {
            load_page(&page_id).map(|page| render_page_context_block(&page, score as f64))
        })
        .collect()
}

fn load_promoted_page_contexts_for_blocks(
    conn: &Connection,
    key: &[u8; 32],
    conversation_scope: Option<&str>,
    existing_blocks: &[knowledge::KnowledgeContextBlock],
    retrieved_blocks: &[knowledge::KnowledgeContextBlock],
) -> Result<(
    Vec<knowledge::KnowledgeContextBlock>,
    std::collections::HashSet<String>,
)> {
    let existing_page_ids = existing_blocks
        .iter()
        .filter(|block| block.document_id.starts_with("page:"))
        .map(|block| block.document_id.clone())
        .collect::<std::collections::HashSet<_>>();
    let mut page_scores = std::collections::BTreeMap::<String, f64>::new();
    let mut promoted_generated_document_ids = std::collections::HashSet::<String>::new();

    for block in retrieved_blocks {
        if !block.document_id.starts_with("generated:") {
            continue;
        }
        let related_page_ids =
            knowledge::compiler::primary_page_ids_for_generated_document(&block.document_id);
        if related_page_ids.is_empty() {
            continue;
        }

        let mut has_allowed_related_page = false;
        for page_id in related_page_ids {
            if existing_page_ids.contains(&page_id) {
                has_allowed_related_page = true;
                continue;
            }
            let Some(page) = crate::db::load_current_knowledge_page(conn, key, &page_id)? else {
                continue;
            };
            if !page_context_allowed_in_scope(&page, conversation_scope) {
                continue;
            }
            has_allowed_related_page = true;
            page_scores
                .entry(page_id)
                .and_modify(|score| *score = score.max(block.score))
                .or_insert(block.score);
        }

        if has_allowed_related_page {
            promoted_generated_document_ids.insert(block.document_id.clone());
        }
    }

    let promoted_blocks = page_scores
        .into_iter()
        .filter_map(|(page_id, score)| {
            crate::db::load_current_knowledge_page(conn, key, &page_id)
                .ok()
                .flatten()
                .filter(|page| page_context_allowed_in_scope(page, conversation_scope))
                .map(|page| render_page_context_block(&page, score))
        })
        .collect::<Vec<_>>();

    Ok((promoted_blocks, promoted_generated_document_ids))
}

pub(super) fn collect_compiled_page_contexts(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    top_k: usize,
    conversation_scope: Option<&str>,
) -> Result<Vec<knowledge::KnowledgeContextBlock>> {
    let _ = knowledge::compiler::refresh_knowledge_pages_if_required(conn, key)?;
    let mut out = Vec::<knowledge::KnowledgeContextBlock>::new();
    let is_planning_query = knowledge::session_digest::is_planning_or_summary_query(question);
    let page_summaries = crate::db::list_knowledge_page_summaries(conn, key)?;
    let answer_excluded_page_ids = crate::db::list_answer_excluded_knowledge_page_ids(conn)?
        .into_iter()
        .collect::<std::collections::HashSet<_>>();
    let muted_page_ids = page_summaries
        .iter()
        .filter(|page| !page.answer_policy.default_allowed)
        .map(|page| page.page_id.clone())
        .collect::<std::collections::HashSet<_>>();
    let excluded_page_ids = muted_page_ids
        .union(&answer_excluded_page_ids)
        .cloned()
        .collect::<std::collections::HashSet<_>>();
    let mut candidate_summaries = page_summaries
        .into_iter()
        .filter(|page| {
            page.answer_policy.default_allowed || page.answer_policy.requires_temporal_framing
        })
        .filter(|page| page_type_allowed_for_conversation_scope(page.page_type, conversation_scope))
        .map(|summary| {
            let lexical_score = lexical_page_match_score(
                question,
                &format!("{}\n{}", summary.title, summary.current_summary),
            );
            (summary, lexical_score)
        })
        .collect::<Vec<_>>();
    candidate_summaries.sort_by(|left, right| {
        right
            .1
            .cmp(&left.1)
            .then_with(|| {
                (right.0.last_used_at_ms.unwrap_or(0)).cmp(&(left.0.last_used_at_ms.unwrap_or(0)))
            })
            .then_with(|| right.0.updated_at_ms.cmp(&left.0.updated_at_ms))
            .then_with(|| left.0.page_id.cmp(&right.0.page_id))
    });
    for block in collect_matching_page_context_blocks(
        question,
        top_k,
        is_planning_query,
        candidate_summaries,
        |page_id| {
            crate::db::load_current_knowledge_page_body(conn, key, page_id)
                .ok()
                .flatten()
        },
        |page_id| {
            crate::db::load_current_knowledge_page(conn, key, page_id)
                .ok()
                .flatten()
        },
    ) {
        out.push(block);
    }

    if out.is_empty() && is_planning_query {
        const PAGE_SIZE: usize = 64;
        let mut offset = 0usize;
        let mut global_fallback_blocks = Vec::<knowledge::KnowledgeContextBlock>::new();
        while out.len() < top_k.max(1) {
            let documents = knowledge::list_knowledge_documents_by_origin(
                conn,
                key,
                knowledge::KnowledgeOriginType::Generated,
                PAGE_SIZE,
                offset,
            )?;
            let fetched = documents.len();
            if documents.is_empty() {
                break;
            }
            for document in documents {
                if !document.memory_feedback.use_for_ask_ai
                    || document.memory_feedback.is_deleted
                    || document.memory_feedback.marked_inaccurate
                {
                    continue;
                }
                if let Some(expected_conversation_id) = conversation_scope {
                    if let Some(actual_conversation_id) =
                        document.anchors.conversation_id.as_deref()
                    {
                        if actual_conversation_id != expected_conversation_id {
                            continue;
                        }
                    }
                }
                if should_exclude_generated_document_for_page_policies(
                    &document.document_id,
                    &excluded_page_ids,
                ) {
                    continue;
                }
                let Some(block) = build_generated_planning_fallback_block(document) else {
                    continue;
                };
                if conversation_scope.is_some() && block.anchors.conversation_id.is_none() {
                    global_fallback_blocks.push(block);
                    continue;
                }
                out.push(block);
            }
            if fetched < PAGE_SIZE {
                break;
            }
            if out.len() >= top_k.max(1) {
                break;
            }
            offset += fetched;
        }
        if out.len() < top_k.max(1) {
            for block in global_fallback_blocks {
                out.push(block);
                if out.len() >= top_k.max(1) {
                    break;
                }
            }
        }
    }
    Ok(out)
}

pub(super) fn rebalance_planning_contexts(
    blocks: &mut Vec<knowledge::KnowledgeContextBlock>,
    max_items: usize,
) {
    let visible_len = blocks.len().min(max_items.max(1));
    if visible_len == 0 {
        return;
    }
    if blocks
        .iter()
        .take(visible_len)
        .any(|block| block.role == knowledge::KnowledgeRole::Evidence)
    {
        return;
    }
    let Some(evidence_index) = blocks
        .iter()
        .position(|block| block.role == knowledge::KnowledgeRole::Evidence)
    else {
        return;
    };
    let evidence = blocks.remove(evidence_index);
    let adjusted_visible_len = blocks.len().min(max_items.max(1));
    let replace_index = (0..adjusted_visible_len)
        .rev()
        .find(|index| {
            let block = &blocks[*index];
            !block.document_id.starts_with("generated:session-digest:")
        })
        .unwrap_or_else(|| adjusted_visible_len.saturating_sub(1));
    blocks.insert(replace_index, evidence);
}

pub(super) fn filter_disabled_generated_memory_blocks(
    conn: &Connection,
    _key: &[u8; 32],
    blocks: Vec<knowledge::KnowledgeContextBlock>,
) -> Result<Vec<knowledge::KnowledgeContextBlock>> {
    let generated_document_ids = blocks
        .iter()
        .filter(|block| block.document_id.starts_with("generated:"))
        .map(|block| block.document_id.clone())
        .collect::<std::collections::BTreeSet<_>>();
    let feedback_by_document_id =
        crate::db::load_knowledge_memory_feedback_map(conn, &generated_document_ids)?;
    let answer_excluded_page_ids = crate::db::list_answer_excluded_knowledge_page_ids(conn)?
        .into_iter()
        .collect::<std::collections::HashSet<_>>();
    let mut out = Vec::with_capacity(blocks.len());
    for block in blocks {
        if !block.document_id.starts_with("generated:") {
            out.push(block);
            continue;
        }
        if should_exclude_generated_document_for_page_policies(
            &block.document_id,
            &answer_excluded_page_ids,
        ) {
            continue;
        }
        let feedback = feedback_by_document_id
            .get(&block.document_id)
            .cloned()
            .unwrap_or_default();
        if feedback.use_for_ask_ai && !feedback.is_deleted && !feedback.marked_inaccurate {
            out.push(block);
        }
    }
    Ok(out)
}

#[allow(dead_code)]
pub(super) fn try_build_knowledge_contexts(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    top_k: usize,
    focus: Focus,
    conversation_id: &str,
    time_window: Option<(i64, i64)>,
) -> Result<Vec<String>> {
    Ok(try_build_knowledge_context_entries(
        conn,
        key,
        question,
        top_k,
        focus,
        conversation_id,
        time_window,
    )?
    .into_iter()
    .map(|entry| entry.rendered_text)
    .collect())
}

pub(super) fn try_build_knowledge_context_entries(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    top_k: usize,
    focus: Focus,
    conversation_id: &str,
    time_window: Option<(i64, i64)>,
) -> Result<Vec<KnowledgeRenderedContextEntry>> {
    if top_k == 0 {
        return Ok(Vec::new());
    }

    let conversation_scope = match focus {
        Focus::AllMemories => None,
        Focus::ThisThread => Some(conversation_id.to_string()),
    };
    let mut request = knowledge::normalize_retrieval_request(
        question,
        conversation_scope.clone(),
        None,
        Some(top_k.max(1)),
        Some(1200),
        None,
    );
    if let Some((start_ms, end_ms)) = time_window {
        request.time_start_ms = Some(start_ms);
        request.time_end_ms = Some(end_ms);
    }

    let is_planning_query = knowledge::session_digest::is_planning_or_summary_query(question);
    let mut blocks =
        collect_compiled_page_contexts(conn, key, question, top_k, conversation_scope.as_deref())?;
    let mut retrieved = filter_disabled_generated_memory_blocks(
        conn,
        key,
        knowledge::retrieve_context_blocks(conn, key, &request)?,
    )?;
    let (mut promoted_pages, promoted_generated_document_ids) =
        load_promoted_page_contexts_for_blocks(
            conn,
            key,
            conversation_scope.as_deref(),
            &blocks,
            &retrieved,
        )?;
    retrieved.retain(|block| !promoted_generated_document_ids.contains(&block.document_id));
    blocks.append(&mut promoted_pages);
    blocks.append(&mut retrieved);

    if is_planning_query {
        blocks.retain(|block| !block.document_id.starts_with("generated:session-digest:"));
        if let Some(digest) = knowledge::session_digest::build_digest_from_blocks(
            question,
            conversation_scope.as_deref(),
            &blocks,
        ) {
            blocks.insert(0, digest);
        }
        sort_planning_contexts(&mut blocks);
    }
    if is_planning_query {
        rebalance_planning_contexts(&mut blocks, top_k.max(1));
    }

    let mut seen_document_ids = std::collections::HashSet::<String>::new();
    blocks.retain(|block| seen_document_ids.insert(block.document_id.clone()));
    if blocks.len() > top_k.max(1) {
        blocks.truncate(top_k.max(1));
    }

    let used_page_ids = blocks
        .iter()
        .filter(|block| block.document_id.starts_with("page:"))
        .map(|block| block.document_id.clone())
        .collect::<Vec<_>>();
    if !used_page_ids.is_empty() {
        let _ = crate::db::touch_knowledge_pages_usage(
            conn,
            &used_page_ids,
            knowledge::usage::now_ms(),
        );
    }

    let used_document_ids = blocks
        .iter()
        .filter(|block| !block.document_id.starts_with("generated:session-digest:"))
        .map(|block| block.document_id.clone())
        .collect::<Vec<_>>();
    let _ = crate::db::touch_knowledge_documents_usage(
        conn,
        &used_document_ids,
        crate::knowledge::usage::now_ms(),
    );

    Ok(blocks
        .into_iter()
        .map(|block| {
            let rendered = match block.anchors.message_id.as_deref() {
                Some(message_id) => {
                    append_message_citation_if_missing(block.rendered_text.clone(), message_id)
                }
                None => block.rendered_text.clone(),
            };
            KnowledgeRenderedContextEntry {
                block,
                rendered_text: rendered,
            }
        })
        .collect())
}

pub(super) fn merge_knowledge_and_legacy_contexts(
    knowledge_contexts: Vec<String>,
    legacy_contexts: Vec<String>,
    top_k: usize,
) -> Vec<String> {
    let max_items = top_k.max(1);
    if max_items == 1 {
        if let Some(ctx) = knowledge_contexts
            .into_iter()
            .find(|ctx| !ctx.trim().is_empty())
        {
            return vec![ctx];
        }
        if let Some(ctx) = legacy_contexts
            .into_iter()
            .find(|ctx| !ctx.trim().is_empty())
        {
            return vec![ctx];
        }
        return Vec::new();
    }

    let mut out: Vec<String> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();

    for ctx in knowledge_contexts {
        if out.len() >= max_items {
            break;
        }
        if ctx.trim().is_empty() {
            continue;
        }
        if seen.insert(ctx.clone()) {
            out.push(ctx);
        }
    }

    for ctx in legacy_contexts {
        if out.len() >= max_items {
            break;
        }
        if ctx.trim().is_empty() {
            continue;
        }
        if seen.insert(ctx.clone()) {
            out.push(ctx);
        }
    }

    out
}

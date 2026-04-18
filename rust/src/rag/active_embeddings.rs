use anyhow::Result;
use rusqlite::Connection;
use std::path::Path;

use crate::db;
use crate::llm::ChatDelta;
use crate::message_citations::{message_citation_link, AnswerEvidenceDirectSource};

use super::attachment_resources::{
    collect_attachment_resources_active, collect_attachment_resources_for_attachment_shas,
};
use super::citations_prompt::build_prompt_with_actions_and_history;
use super::context_selection::{build_contexts_v2, lite_score, render_context_item_for_prompt};
use super::evidence::{
    build_attachment_resource_direct_source, build_direct_sources_for_context_candidate,
};
use super::{
    ask_ai_stream_and_persist, build_recent_conversation_history,
    build_recent_conversation_history_in_range, build_todo_thread_context,
    build_todo_thread_context_in_range, AnswerProvider, AskAiResult, ContextItem, ContextSource,
    ContextWithEvidence, Focus,
};

const TIME_WINDOW_MESSAGE_LIMIT: usize = 800;
const TIME_WINDOW_TODO_ACTIVITY_LIMIT: usize = 300;
const TIME_WINDOW_EVENT_LIMIT: usize = 200;
const ACTIVE_EMBEDDINGS_EVENT_LIMIT: usize = 200;
const ACTIVE_EMBEDDINGS_CANDIDATE_LIMIT_CAP: usize = 128;
const TIME_WINDOW_ATTACHMENT_SEARCH_MAX_LIMIT: usize = 512;

fn active_embedding_candidate_limit(top_k: usize) -> usize {
    if top_k == 0 {
        8
    } else {
        (top_k.saturating_mul(8))
            .min(ACTIVE_EMBEDDINGS_CANDIDATE_LIMIT_CAP)
            .max(top_k)
    }
}

fn collect_time_window_attachment_resources(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: Option<&str>,
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<super::attachment_resources::AttachmentResourcesBundle> {
    let attachment_shas = list_attachment_shas_in_time_window(
        conn,
        key,
        conversation_id,
        time_start_ms,
        time_end_ms,
    )?;
    collect_attachment_resources_for_attachment_shas(conn, key, attachment_shas)
}

fn list_attachment_shas_in_time_window(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: Option<&str>,
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<Vec<String>> {
    let mut attachment_shas = Vec::<String>::new();
    for message in db::list_memory_messages_in_range_recent(
        conn,
        key,
        conversation_id,
        time_start_ms,
        time_end_ms,
        TIME_WINDOW_MESSAGE_LIMIT as i64,
    )? {
        for attachment in db::list_message_attachments(conn, key, &message.id)? {
            attachment_shas.push(attachment.sha256);
        }
    }
    Ok(attachment_shas)
}

fn refresh_active_embedding_indexes(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
) -> Result<()> {
    db::process_pending_message_embeddings_active(conn, key, app_dir, 1024)?;
    db::process_pending_todo_embeddings_active(conn, key, app_dir, 1024)?;
    db::process_pending_todo_activity_embeddings_active(conn, key, app_dir, 1024)?;
    Ok(())
}

fn build_time_window_todo_activity_text(activity: &db::TodoActivity) -> String {
    let mut text = format!(
        "todo_id={} type={} created_at_ms={}",
        activity.todo_id, activity.activity_type, activity.created_at_ms
    );
    if let Some(from) = activity.from_status.as_deref() {
        text.push_str(&format!(" from={from}"));
    }
    if let Some(to) = activity.to_status.as_deref() {
        text.push_str(&format!(" to={to}"));
    }
    if let Some(content) = activity.content.as_deref() {
        text.push_str(&format!(" content={content}"));
    }
    text
}

fn build_time_window_event_text(event: &db::Event) -> String {
    format!(
        "{} (start_at_ms={}, end_at_ms={}, tz={})",
        event.title, event.start_at_ms, event.end_at_ms, event.tz
    )
}

fn retain_most_relevant_items(
    question: &str,
    items: Vec<(String, ContextItem)>,
    limit: usize,
) -> Vec<ContextItem> {
    if limit == 0 || items.len() <= limit {
        return items.into_iter().map(|(_, item)| item).collect::<Vec<_>>();
    }

    let mut ranked = items
        .into_iter()
        .enumerate()
        .map(|(index, (score_text, item))| {
            (
                index,
                lite_score(question, &score_text),
                item.created_at_ms,
                item,
            )
        })
        .collect::<Vec<_>>();

    ranked.sort_by(|left, right| {
        right
            .1
            .cmp(&left.1)
            .then_with(|| right.2.cmp(&left.2))
            .then_with(|| left.0.cmp(&right.0))
    });
    ranked.truncate(limit);
    ranked.sort_by_key(|entry| entry.0);
    ranked
        .into_iter()
        .map(|(_, _, _, item)| item)
        .collect::<Vec<_>>()
}

fn collect_time_window_candidates(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    question: &str,
    conversation_filter: Option<&str>,
    time_start_ms: i64,
    time_end_ms: i64,
    top_k: usize,
) -> Result<Vec<ContextItem>> {
    let mut candidates = Vec::<ContextItem>::new();

    for message in db::list_memory_messages_in_range_recent(
        conn,
        key,
        conversation_filter,
        time_start_ms,
        time_end_ms,
        TIME_WINDOW_MESSAGE_LIMIT as i64,
    )? {
        let context = db::build_message_rag_context(conn, key, &message.id, &message.content)
            .unwrap_or(message.content);
        let citation_suffix = message_citation_link(&message.id);
        candidates.push(ContextItem {
            source: ContextSource::Message,
            id: message.id,
            created_at_ms: message.created_at_ms,
            distance: None,
            text: context,
            citation_suffix,
        });
    }

    let activity_candidates =
        db::list_todo_activities_in_range(conn, key, time_start_ms, time_end_ms)?
            .into_iter()
            .map(|activity| {
                let text = build_time_window_todo_activity_text(&activity);
                let score_text = activity
                    .content
                    .as_deref()
                    .filter(|value| !value.trim().is_empty())
                    .map(ToOwned::to_owned)
                    .unwrap_or_else(|| {
                        format!(
                            "{} {} {}",
                            activity.activity_type,
                            activity.from_status.as_deref().unwrap_or_default(),
                            activity.to_status.as_deref().unwrap_or_default(),
                        )
                    });
                (
                    score_text,
                    ContextItem {
                        source: ContextSource::TodoActivity,
                        id: activity.id,
                        created_at_ms: activity.created_at_ms,
                        distance: None,
                        text,
                        citation_suffix: None,
                    },
                )
            })
            .collect::<Vec<_>>();
    candidates.extend(retain_most_relevant_items(
        question,
        activity_candidates,
        TIME_WINDOW_TODO_ACTIVITY_LIMIT,
    ));

    let event_candidates = db::list_events_in_range(conn, key, time_start_ms, time_end_ms)?
        .into_iter()
        .map(|event| {
            let text = build_time_window_event_text(&event);
            (
                event.title.clone(),
                ContextItem {
                    source: ContextSource::Event,
                    id: event.id,
                    created_at_ms: event.start_at_ms,
                    distance: None,
                    text,
                    citation_suffix: None,
                },
            )
        })
        .collect::<Vec<_>>();
    candidates.extend(retain_most_relevant_items(
        question,
        event_candidates,
        TIME_WINDOW_EVENT_LIMIT,
    ));

    let mut seen_todos = std::collections::HashSet::<String>::new();
    for todo in db::list_todos(conn, key)?.into_iter() {
        if !seen_todos.insert(todo.id.clone()) {
            continue;
        }
        let due_in_range = todo
            .due_at_ms
            .is_some_and(|ms| ms >= time_start_ms && ms < time_end_ms);
        let review_in_range = todo
            .next_review_at_ms
            .is_some_and(|ms| ms >= time_start_ms && ms < time_end_ms);
        if !due_in_range && !review_in_range {
            continue;
        }

        let text =
            build_todo_thread_context_in_range(conn, key, &todo.id, time_start_ms, time_end_ms)?;
        candidates.push(ContextItem {
            source: ContextSource::TodoThread,
            id: todo.id,
            created_at_ms: todo.created_at_ms,
            distance: None,
            text,
            citation_suffix: None,
        });
    }

    let attachment_shas = list_attachment_shas_in_time_window(
        conn,
        key,
        conversation_filter,
        time_start_ms,
        time_end_ms,
    )?;
    if attachment_shas.is_empty() {
        return Ok(candidates);
    }

    let allowed_attachment_shas = attachment_shas
        .into_iter()
        .collect::<std::collections::HashSet<_>>();
    db::process_attachment_text_chunks(conn, key, 256)?;
    db::process_pending_attachment_chunk_embeddings_active(conn, key, app_dir, 2048)?;
    let mut search_limit = top_k.saturating_mul(2).max(top_k).max(1);
    let max_search_limit = TIME_WINDOW_ATTACHMENT_SEARCH_MAX_LIMIT.max(search_limit);
    let filtered_chunks = loop {
        let filtered = db::search_similar_attachment_chunks_active(
            conn,
            key,
            app_dir,
            question,
            search_limit,
        )?
        .into_iter()
        .filter(|chunk| allowed_attachment_shas.contains(&chunk.attachment_sha256))
        .collect::<Vec<_>>();
        if filtered.len() >= top_k || search_limit >= max_search_limit {
            break filtered;
        }

        let next_limit = search_limit.saturating_mul(2).min(max_search_limit);
        if next_limit == search_limit {
            break filtered;
        }
        search_limit = next_limit;
    };
    for chunk in filtered_chunks.into_iter().take(top_k) {
        let text = match db::read_attachment_chunk_text(
            conn,
            key,
            &chunk.attachment_sha256,
            &chunk.kind,
            chunk.chunk_index,
        ) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let created_at_ms = db::read_attachment_by_sha256(conn, &chunk.attachment_sha256)
            .ok()
            .flatten()
            .map(|attachment| attachment.created_at_ms)
            .unwrap_or_default();
        let citation = format!(
            "[Attachment](secondloop://attachment/{}?kind={}&chunk={})",
            chunk.attachment_sha256, chunk.kind, chunk.chunk_index
        );
        let context = format!(
            "ATTACHMENT_CHUNK {} {}#{}\n{}\n{}",
            chunk.attachment_sha256, chunk.kind, chunk.chunk_index, text, citation
        );
        candidates.push(ContextItem {
            source: ContextSource::AttachmentChunk,
            id: format!(
                "{}:{}:{}",
                chunk.attachment_sha256, chunk.kind, chunk.chunk_index
            ),
            created_at_ms,
            distance: Some(chunk.distance),
            text: context,
            citation_suffix: None,
        });
    }

    Ok(candidates)
}

#[allow(clippy::too_many_arguments)]
fn collect_active_embedding_candidates(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
) -> Result<(
    Vec<ContextItem>,
    super::attachment_resources::AttachmentResourcesBundle,
)> {
    let mut candidates = Vec::<ContextItem>::new();
    let candidate_limit = active_embedding_candidate_limit(top_k);

    let similar_messages = match focus {
        Focus::AllMemories => {
            db::search_similar_messages_active(conn, key, app_dir, question, candidate_limit)?
        }
        Focus::ThisThread => db::search_similar_messages_in_conversation_active(
            conn,
            key,
            app_dir,
            conversation_id,
            question,
            candidate_limit,
        )?,
    };
    for sm in similar_messages {
        let context = db::build_message_rag_context(conn, key, &sm.message.id, &sm.message.content)
            .unwrap_or_else(|_| sm.message.content.clone());
        let citation_suffix = message_citation_link(&sm.message.id);
        candidates.push(ContextItem {
            source: ContextSource::Message,
            id: sm.message.id,
            created_at_ms: sm.message.created_at_ms,
            distance: Some(sm.distance),
            text: context,
            citation_suffix,
        });
    }

    let mut seen_todos = std::collections::HashSet::new();
    for st in db::search_similar_todo_threads_active(conn, key, app_dir, question, candidate_limit)?
    {
        if !seen_todos.insert(st.todo_id.clone()) {
            continue;
        }
        let todo = match db::get_todo(conn, key, &st.todo_id) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let ctx = match build_todo_thread_context(conn, key, &st.todo_id) {
            Ok(value) => value,
            Err(_) => continue,
        };
        candidates.push(ContextItem {
            source: ContextSource::TodoThread,
            id: st.todo_id,
            created_at_ms: todo.created_at_ms,
            distance: Some(st.distance),
            text: ctx,
            citation_suffix: None,
        });
    }

    let event_candidates = db::list_events(conn, key)?
        .into_iter()
        .map(|event| {
            let text = build_time_window_event_text(&event);
            (
                event.title.clone(),
                ContextItem {
                    source: ContextSource::Event,
                    id: event.id,
                    created_at_ms: event.start_at_ms,
                    distance: None,
                    text,
                    citation_suffix: None,
                },
            )
        })
        .collect::<Vec<_>>();
    candidates.extend(retain_most_relevant_items(
        question,
        event_candidates,
        ACTIVE_EMBEDDINGS_EVENT_LIMIT,
    ));

    let attachment_resources =
        collect_attachment_resources_active(conn, key, app_dir, question, top_k)
            .unwrap_or_default();
    for chunk in &attachment_resources.chunks {
        let citation = format!(
            "[Attachment](secondloop://attachment/{}?kind={}&chunk={})",
            chunk.attachment_sha256, chunk.kind, chunk.chunk_index
        );
        let context = format!(
            "ATTACHMENT_CHUNK {} {}#{}\n{}\n{}",
            chunk.attachment_sha256, chunk.kind, chunk.chunk_index, chunk.text, citation
        );
        candidates.push(ContextItem {
            source: ContextSource::AttachmentChunk,
            id: format!(
                "{}:{}:{}",
                chunk.attachment_sha256, chunk.kind, chunk.chunk_index
            ),
            created_at_ms: chunk.created_at_ms,
            distance: Some(chunk.distance),
            text: context,
            citation_suffix: None,
        });
    }

    Ok((candidates, attachment_resources))
}

#[allow(clippy::too_many_arguments)]
pub(super) fn ask_ai_with_provider_using_active_embeddings(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    let mut contexts: Vec<ContextWithEvidence> = Vec::new();
    let mut resources_catalog: Option<String> = None;
    let mut attachment_direct_sources = Vec::<AnswerEvidenceDirectSource>::new();

    if top_k > 0 {
        refresh_active_embedding_indexes(conn, key, app_dir)?;

        let top_k = top_k.max(1);
        let (candidates, attachment_resources) = collect_active_embedding_candidates(
            conn,
            key,
            app_dir,
            conversation_id,
            question,
            top_k,
            focus,
        )?;
        attachment_direct_sources = attachment_resources
            .resources
            .iter()
            .map(|resource| {
                build_attachment_resource_direct_source(
                    &resource.attachment_sha256,
                    &resource.label,
                    resource.created_at_ms,
                )
            })
            .collect();
        let selected = build_contexts_v2(question, candidates.clone(), top_k);
        let mut context_by_text = std::collections::HashMap::<String, ContextWithEvidence>::new();
        for candidate in candidates {
            let rendered_text = render_context_item_for_prompt(question, &candidate)
                .unwrap_or_else(|| candidate.text.clone());
            let direct_sources = build_direct_sources_for_context_candidate(conn, key, &candidate);
            context_by_text.insert(
                rendered_text.clone(),
                ContextWithEvidence {
                    text: rendered_text,
                    direct_sources,
                },
            );
        }
        contexts = selected
            .into_iter()
            .filter_map(|text| context_by_text.remove(&text))
            .collect();
        resources_catalog = attachment_resources.catalog_markdown;
    }

    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let actions = super::build_actions_context(conn, key, question)?;
    if let Some(action_context) = actions.as_ref() {
        attachment_direct_sources.extend(action_context.direct_sources.iter().cloned());
    }
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts
            .iter()
            .map(|ctx| ctx.text.clone())
            .collect::<Vec<_>>(),
        actions.as_ref().map(|bundle| bundle.text.as_str()),
        history.as_deref(),
        resources_catalog.as_deref(),
    );

    ask_ai_stream_and_persist(
        conn,
        key,
        conversation_id,
        question,
        &prompt,
        &contexts,
        &attachment_direct_sources,
        provider,
        on_event,
    )
}

#[allow(clippy::too_many_arguments)]
pub(super) fn ask_ai_with_provider_using_active_embeddings_time_window(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    time_start_ms: i64,
    time_end_ms: i64,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    let mut contexts: Vec<ContextWithEvidence> = Vec::new();
    let conversation_filter = match focus {
        Focus::AllMemories => None,
        Focus::ThisThread => Some(conversation_id),
    };

    if top_k > 0 {
        let top_k = top_k.max(1);
        let candidates = collect_time_window_candidates(
            conn,
            key,
            app_dir,
            question,
            conversation_filter,
            time_start_ms,
            time_end_ms,
            top_k,
        )?;

        let selected = build_contexts_v2(question, candidates.clone(), top_k);
        let mut context_by_text = std::collections::HashMap::<String, ContextWithEvidence>::new();
        for candidate in candidates {
            let rendered_text = render_context_item_for_prompt(question, &candidate)
                .unwrap_or_else(|| candidate.text.clone());
            let direct_sources = build_direct_sources_for_context_candidate(conn, key, &candidate);
            context_by_text.insert(
                rendered_text.clone(),
                ContextWithEvidence {
                    text: rendered_text,
                    direct_sources,
                },
            );
        }
        contexts = selected
            .into_iter()
            .filter_map(|text| context_by_text.remove(&text))
            .collect();
    }

    let attachment_resources = collect_time_window_attachment_resources(
        conn,
        key,
        conversation_filter,
        time_start_ms,
        time_end_ms,
    )?;
    let history = build_recent_conversation_history_in_range(
        conn,
        key,
        conversation_id,
        time_start_ms,
        time_end_ms,
    )?;
    let actions =
        super::build_actions_context_in_range(conn, key, question, time_start_ms, time_end_ms)?;
    let mut attachment_direct_sources = attachment_resources
        .resources
        .iter()
        .map(|resource| {
            build_attachment_resource_direct_source(
                &resource.attachment_sha256,
                &resource.label,
                resource.created_at_ms,
            )
        })
        .collect::<Vec<_>>();
    if let Some(action_context) = actions.as_ref() {
        attachment_direct_sources.extend(action_context.direct_sources.iter().cloned());
    }
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts
            .iter()
            .map(|ctx| ctx.text.clone())
            .collect::<Vec<_>>(),
        actions.as_ref().map(|bundle| bundle.text.as_str()),
        history.as_deref(),
        attachment_resources.catalog_markdown.as_deref(),
    );

    ask_ai_stream_and_persist(
        conn,
        key,
        conversation_id,
        question,
        &prompt,
        &contexts,
        &attachment_direct_sources,
        provider,
        on_event,
    )
}

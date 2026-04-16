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
use super::context_selection::{build_contexts_v2, render_context_item_for_prompt};
use super::evidence::{
    build_attachment_resource_direct_source, build_direct_sources_for_context_candidate,
    build_direct_sources_from_knowledge_entry, build_memory_card_from_document,
    context_usage_reason,
};
use super::knowledge_contexts::{
    merge_knowledge_and_legacy_contexts, try_build_knowledge_context_entries,
};
use super::{
    ask_ai_stream_and_persist, build_actions_context, build_recent_conversation_history,
    build_recent_conversation_history_in_range, build_todo_thread_context, now_ms, AnswerProvider,
    AskAiResult, ContextItem, ContextSource, ContextWithEvidence, Focus,
};

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
        800,
    )? {
        for attachment in db::list_message_attachments(conn, key, &message.id)? {
            attachment_shas.push(attachment.sha256);
        }
    }
    Ok(attachment_shas)
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
        let knowledge_entries = try_build_knowledge_context_entries(
            conn,
            key,
            question,
            top_k,
            focus,
            conversation_id,
            None,
        )?;
        let knowledge_contexts = knowledge_entries
            .iter()
            .map(|entry| entry.rendered_text.clone())
            .collect::<Vec<_>>();
        if !super::fallback::should_use_legacy_retrieval_fallback(&knowledge_contexts) {
            let why_used = context_usage_reason(question);
            contexts = knowledge_entries
                .into_iter()
                .map(|entry| ContextWithEvidence {
                    text: entry.rendered_text.clone(),
                    direct_sources: build_direct_sources_from_knowledge_entry(conn, key, &entry),
                    memory_cards: build_memory_card_from_document(
                        conn,
                        key,
                        &entry.block.document_id,
                        &why_used,
                    )
                    .into_iter()
                    .collect(),
                })
                .collect();
        } else {
            db::process_pending_message_embeddings_active(conn, key, app_dir, 1024)?;
            db::process_pending_todo_embeddings_active(conn, key, app_dir, 1024)?;
            db::process_pending_todo_activity_embeddings_active(conn, key, app_dir, 1024)?;

            let legacy_top_k = top_k.saturating_sub(knowledge_contexts.len()).max(1);

            let top_k_candidate_messages =
                (legacy_top_k.saturating_mul(8)).min(200).max(legacy_top_k);
            let top_k_candidate_todos = (legacy_top_k.saturating_mul(4)).min(80).max(legacy_top_k);

            let similar_messages = match focus {
                Focus::AllMemories => db::search_similar_messages_active(
                    conn,
                    key,
                    app_dir,
                    question,
                    top_k_candidate_messages,
                )?,
                Focus::ThisThread => db::search_similar_messages_in_conversation_active(
                    conn,
                    key,
                    app_dir,
                    conversation_id,
                    question,
                    top_k_candidate_messages,
                )?,
            };

            let similar_todos = db::search_similar_todo_threads_active(
                conn,
                key,
                app_dir,
                question,
                top_k_candidate_todos,
            )?;
            let attachment_resources =
                collect_attachment_resources_active(conn, key, app_dir, question, legacy_top_k)
                    .unwrap_or_default();
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
            let external_chunks = db::search_similar_external_document_chunks_active(
                app_dir,
                key,
                question,
                top_k_candidate_messages,
            )
            .unwrap_or_default();

            let mut candidates: Vec<ContextItem> = Vec::new();
            for sm in similar_messages {
                let context =
                    db::build_message_rag_context(conn, key, &sm.message.id, &sm.message.content)
                        .unwrap_or_else(|_| sm.message.content.clone());
                candidates.push(ContextItem {
                    source: ContextSource::Message,
                    id: sm.message.id.clone(),
                    created_at_ms: sm.message.created_at_ms,
                    distance: Some(sm.distance),
                    text: context,
                    citation_suffix: message_citation_link(&sm.message.id),
                });
            }

            let mut seen_todos = std::collections::HashSet::new();
            for st in similar_todos {
                if !seen_todos.insert(st.todo_id.clone()) {
                    continue;
                }
                let todo = match db::get_todo(conn, key, &st.todo_id) {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                let ctx = match build_todo_thread_context(conn, key, &st.todo_id) {
                    Ok(v) => v,
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

            for chunk in attachment_resources.chunks {
                let citation = format!(
                    "[Attachment](secondloop://attachment/{}?kind={}&chunk={})",
                    chunk.attachment_sha256, chunk.kind, chunk.chunk_index
                );
                let context = format!("{}\n{}", chunk.text, citation);
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

            for chunk in external_chunks {
                let context = match db::build_external_document_chunk_rag_context(
                    app_dir,
                    key,
                    &chunk.doc_id,
                    chunk.chunk_index,
                ) {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                candidates.push(ContextItem {
                    source: ContextSource::ExternalDocument,
                    id: format!("{}:{}", chunk.doc_id, chunk.chunk_index),
                    created_at_ms: chunk.created_at_ms,
                    distance: Some(chunk.distance),
                    text: context,
                    citation_suffix: None,
                });
            }

            let ranking_created_at_ms = now_ms();
            let ranking_candidates = candidates
                .iter()
                .cloned()
                .map(|mut candidate| {
                    candidate.created_at_ms = ranking_created_at_ms;
                    candidate
                })
                .collect::<Vec<_>>();
            let legacy_contexts = build_contexts_v2(question, ranking_candidates, legacy_top_k);
            let merged = merge_knowledge_and_legacy_contexts(
                knowledge_contexts.clone(),
                legacy_contexts,
                top_k,
            );
            let why_used = context_usage_reason(question);
            let mut context_by_text =
                std::collections::HashMap::<String, ContextWithEvidence>::new();
            for entry in knowledge_entries {
                context_by_text.insert(
                    entry.rendered_text.clone(),
                    ContextWithEvidence {
                        text: entry.rendered_text.clone(),
                        direct_sources: build_direct_sources_from_knowledge_entry(
                            conn, key, &entry,
                        ),
                        memory_cards: build_memory_card_from_document(
                            conn,
                            key,
                            &entry.block.document_id,
                            &why_used,
                        )
                        .into_iter()
                        .collect(),
                    },
                );
            }
            for candidate in candidates {
                let rendered_text = render_context_item_for_prompt(question, &candidate)
                    .unwrap_or_else(|| candidate.text.clone());
                let direct_sources =
                    build_direct_sources_for_context_candidate(conn, key, &candidate);
                context_by_text.insert(
                    rendered_text.clone(),
                    ContextWithEvidence {
                        text: rendered_text,
                        direct_sources,
                        memory_cards: Vec::new(),
                    },
                );
            }
            contexts = merged
                .into_iter()
                .filter_map(|text| context_by_text.remove(&text))
                .collect();
            resources_catalog = attachment_resources.catalog_markdown;
        }
    }
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts
            .iter()
            .map(|ctx| ctx.text.clone())
            .collect::<Vec<_>>(),
        actions.as_deref(),
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
        let knowledge_entries = try_build_knowledge_context_entries(
            conn,
            key,
            question,
            top_k.max(1),
            focus,
            conversation_id,
            Some((time_start_ms, time_end_ms)),
        )?;
        let knowledge_contexts = knowledge_entries
            .iter()
            .map(|entry| entry.rendered_text.clone())
            .collect::<Vec<_>>();
        if super::fallback::should_use_legacy_retrieval_fallback(&knowledge_contexts) {
            let legacy_top_k = top_k.saturating_sub(knowledge_contexts.len()).max(1);
            let mut candidates: Vec<ContextItem> = Vec::new();

            for m in db::list_memory_messages_in_range(
                conn,
                key,
                conversation_filter,
                time_start_ms,
                time_end_ms,
                800,
            )? {
                let context = db::build_message_rag_context(conn, key, &m.id, &m.content)
                    .unwrap_or(m.content);
                let citation_suffix = message_citation_link(&m.id);
                candidates.push(ContextItem {
                    source: ContextSource::Message,
                    id: m.id,
                    created_at_ms: m.created_at_ms,
                    distance: None,
                    text: context,
                    citation_suffix,
                });
            }

            for a in db::list_todo_activities_in_range(conn, key, time_start_ms, time_end_ms)?
                .into_iter()
                .take(300)
            {
                let mut text = format!(
                    "TODO_ACTIVITY todo_id={} type={} created_at_ms={}",
                    a.todo_id, a.activity_type, a.created_at_ms
                );
                if let Some(from) = a.from_status.as_deref() {
                    text.push_str(&format!(" from={from}"));
                }
                if let Some(to) = a.to_status.as_deref() {
                    text.push_str(&format!(" to={to}"));
                }
                if let Some(content) = a.content.as_deref() {
                    text.push_str(&format!(" content={content}"));
                }
                candidates.push(ContextItem {
                    source: ContextSource::TodoActivity,
                    id: a.id,
                    created_at_ms: a.created_at_ms,
                    distance: None,
                    text,
                    citation_suffix: None,
                });
            }

            for e in db::list_events_in_range(conn, key, time_start_ms, time_end_ms)?
                .into_iter()
                .take(200)
            {
                let text = format!(
                    "EVENT {} (start_at_ms={}, end_at_ms={}, tz={})",
                    e.title, e.start_at_ms, e.end_at_ms, e.tz
                );
                candidates.push(ContextItem {
                    source: ContextSource::Event,
                    id: e.id,
                    created_at_ms: e.start_at_ms,
                    distance: None,
                    text,
                    citation_suffix: None,
                });
            }

            let mut seen_todos: std::collections::HashSet<String> =
                std::collections::HashSet::new();
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

                let ctx = build_todo_thread_context(conn, key, &todo.id)?;
                candidates.push(ContextItem {
                    source: ContextSource::TodoThread,
                    id: todo.id,
                    created_at_ms: todo.created_at_ms,
                    distance: None,
                    text: ctx,
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
            if !attachment_shas.is_empty() {
                let allowed_attachment_shas = attachment_shas
                    .into_iter()
                    .collect::<std::collections::HashSet<_>>();
                db::process_attachment_text_chunks(conn, key, 256)?;
                for chunk in db::search_similar_attachment_chunks_active(
                    conn,
                    key,
                    app_dir,
                    question,
                    legacy_top_k.saturating_mul(2).max(legacy_top_k),
                )?
                .into_iter()
                .filter(|chunk| allowed_attachment_shas.contains(&chunk.attachment_sha256))
                .take(legacy_top_k)
                {
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
                    let created_at_ms =
                        db::read_attachment_by_sha256(conn, &chunk.attachment_sha256)
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
            }

            for chunk in db::search_similar_external_document_chunks_active(
                app_dir,
                key,
                question,
                legacy_top_k,
            )
            .unwrap_or_default()
            .into_iter()
            .filter(|chunk| {
                chunk.created_at_ms >= time_start_ms && chunk.created_at_ms < time_end_ms
            }) {
                let context = match db::build_external_document_chunk_rag_context(
                    app_dir,
                    key,
                    &chunk.doc_id,
                    chunk.chunk_index,
                ) {
                    Ok(value) => value,
                    Err(_) => continue,
                };
                candidates.push(ContextItem {
                    source: ContextSource::ExternalDocument,
                    id: format!("{}:{}", chunk.doc_id, chunk.chunk_index),
                    created_at_ms: chunk.created_at_ms,
                    distance: Some(chunk.distance),
                    text: context,
                    citation_suffix: None,
                });
            }

            let legacy_contexts = build_contexts_v2(question, candidates.clone(), legacy_top_k);
            let merged = merge_knowledge_and_legacy_contexts(
                knowledge_contexts.clone(),
                legacy_contexts,
                top_k.max(1),
            );
            let why_used = context_usage_reason(question);
            let mut context_by_text =
                std::collections::HashMap::<String, ContextWithEvidence>::new();
            for entry in knowledge_entries {
                context_by_text.insert(
                    entry.rendered_text.clone(),
                    ContextWithEvidence {
                        text: entry.rendered_text.clone(),
                        direct_sources: build_direct_sources_from_knowledge_entry(
                            conn, key, &entry,
                        ),
                        memory_cards: build_memory_card_from_document(
                            conn,
                            key,
                            &entry.block.document_id,
                            &why_used,
                        )
                        .into_iter()
                        .collect(),
                    },
                );
            }
            for candidate in candidates {
                let rendered_text = render_context_item_for_prompt(question, &candidate)
                    .unwrap_or_else(|| candidate.text.clone());
                let direct_sources =
                    build_direct_sources_for_context_candidate(conn, key, &candidate);
                context_by_text.insert(
                    rendered_text.clone(),
                    ContextWithEvidence {
                        text: rendered_text,
                        direct_sources,
                        memory_cards: Vec::new(),
                    },
                );
            }
            contexts = merged
                .into_iter()
                .filter_map(|text| context_by_text.remove(&text))
                .collect();
        } else {
            let why_used = context_usage_reason(question);
            contexts = knowledge_entries
                .into_iter()
                .map(|entry| ContextWithEvidence {
                    text: entry.rendered_text.clone(),
                    direct_sources: build_direct_sources_from_knowledge_entry(conn, key, &entry),
                    memory_cards: build_memory_card_from_document(
                        conn,
                        key,
                        &entry.block.document_id,
                        &why_used,
                    )
                    .into_iter()
                    .collect(),
                })
                .collect();
        }
    }

    let attachment_resources = collect_time_window_attachment_resources(
        conn,
        key,
        conversation_filter,
        time_start_ms,
        time_end_ms,
    )?;
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history_in_range(
        conn,
        key,
        conversation_id,
        time_start_ms,
        time_end_ms,
    )?;
    let attachment_direct_sources = attachment_resources
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
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts
            .iter()
            .map(|ctx| ctx.text.clone())
            .collect::<Vec<_>>(),
        actions.as_deref(),
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

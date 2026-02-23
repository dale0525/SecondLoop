pub fn build_prompt(question: &str, contexts: &[String]) -> String {
    build_prompt_with_actions(question, contexts, None)
}

fn collect_attachment_chunk_hits(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    top_k: usize,
) -> Result<Vec<db::SimilarAttachmentChunk>> {
    db::process_attachment_chunk_index_default(conn, key, 512)?;
    db::process_pending_attachment_chunk_embeddings_default(conn, key, 2048)?;
    db::search_similar_attachment_chunks_default(conn, key, question, top_k.max(1))
}

fn attachment_chunk_context_text(hit: &db::SimilarAttachmentChunk) -> String {
    format!(
        "sha={} kind={} chunk={} link={}\n{}",
        hit.attachment_sha256,
        hit.kind,
        hit.chunk_index,
        build_attachment_chunk_link(&hit.attachment_sha256, &hit.kind, hit.chunk_index),
        hit.text
    )
}

fn attachment_created_at_ms(conn: &Connection, attachment_sha256: &str) -> i64 {
    db::read_attachment_by_sha_optional(conn, attachment_sha256)
        .ok()
        .flatten()
        .map(|v| v.created_at_ms)
        .unwrap_or_else(now_ms)
}

pub fn ask_ai_with_provider(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    // Ensure existing messages are embedded before searching.
    db::process_pending_message_embeddings_default(conn, key, 1024)?;
    db::process_pending_todo_embeddings_default(conn, key, 1024)?;
    db::process_pending_todo_activity_embeddings_default(conn, key, 1024)?;

    let top_k = top_k.max(1);

    let similar_messages = match focus {
        Focus::AllMemories => db::search_similar_messages_default(conn, key, question, top_k)?,
        Focus::ThisThread => db::search_similar_messages_in_conversation_default(
            conn,
            key,
            conversation_id,
            question,
            top_k,
        )?,
    };
    let similar_todos = db::search_similar_todo_threads_default(conn, key, question, top_k)?;
    let attachment_hits = collect_attachment_chunk_hits(conn, key, question, top_k)?;

    let mut contexts_with_distance: Vec<(f64, String)> = Vec::new();
    for sm in similar_messages {
        let context = db::build_message_rag_context(conn, key, &sm.message.id, &sm.message.content)
            .unwrap_or_else(|_| sm.message.content.clone());
        contexts_with_distance.push((sm.distance, context));
    }
    let mut seen_todos = std::collections::HashSet::new();
    for st in similar_todos {
        if !seen_todos.insert(st.todo_id.clone()) {
            continue;
        }
        let ctx = match build_todo_thread_context(conn, key, &st.todo_id) {
            Ok(v) => v,
            Err(_) => continue,
        };
        contexts_with_distance.push((st.distance, ctx));
    }
    for hit in &attachment_hits {
        let ctx = attachment_chunk_context_text(hit);
        contexts_with_distance.push((hit.distance, ctx));
    }

    contexts_with_distance
        .sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    contexts_with_distance.truncate(top_k);
    let contexts: Vec<String> = contexts_with_distance
        .into_iter()
        .map(|(_, ctx)| ctx)
        .collect();
    let resources_catalog = build_attachment_resources_catalog(conn, key, &attachment_hits)?;
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts,
        actions.as_deref(),
        history.as_deref(),
        resources_catalog.as_deref(),
    );

    let mut has_text = false;
    let mut assistant_text = String::new();
    let result = provider.stream_answer(&prompt, &mut |ev| {
        let done = ev.done;
        let text_delta = ev.text_delta.clone();
        on_event(ev)?;

        if !done && !text_delta.is_empty() {
            has_text = true;
            assistant_text.push_str(&text_delta);
        }

        Ok(())
    });

    match result {
        Ok(()) => {
            if !has_text {
                return Err(anyhow!("empty response from LLM"));
            }

            let user_message =
                db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
            let assistant_message = db::insert_message_non_memory(
                conn,
                key,
                conversation_id,
                "assistant",
                &assistant_text,
            )?;

            Ok(AskAiResult {
                user_message_id: user_message.id,
                assistant_message_id: assistant_message.id,
            })
        }
        Err(e) => Err(e),
    }
}

#[allow(clippy::too_many_arguments)]
pub fn ask_ai_with_provider_using_embedder<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    let mut contexts: Vec<String> = Vec::new();
    let mut attachment_hits: Vec<db::SimilarAttachmentChunk> = Vec::new();
    if top_k > 0 {
        // Avoid wiping the current index if the embedder is misconfigured/unreachable.
        let mut probe = embedder.embed(&[format!("query: {question}")])?;
        if probe.len() != 1 {
            return Err(anyhow!(
                "embedder output length mismatch: expected 1, got {}",
                probe.len()
            ));
        }
        let query_vector = probe.pop().unwrap_or_default();
        let dim = query_vector.len();
        if dim == 0 {
            return Err(anyhow!("embedder returned empty embeddings"));
        }

        db::set_active_embedding_model(conn, embedder.model_name(), dim)?;
        db::process_pending_message_embeddings(conn, key, embedder, 1024)?;
        db::process_pending_todo_embeddings(conn, key, embedder, 1024)?;
        db::process_pending_todo_activity_embeddings(conn, key, embedder, 1024)?;

        let top_k = top_k.max(1);

        let similar_messages = match focus {
            Focus::AllMemories => db::search_similar_messages_by_embedding(
                conn,
                key,
                embedder.model_name(),
                &query_vector,
                top_k,
            )?,
            Focus::ThisThread => db::search_similar_messages_in_conversation_by_embedding(
                conn,
                key,
                embedder.model_name(),
                conversation_id,
                &query_vector,
                top_k,
            )?,
        };

        let similar_todos = db::search_similar_todo_threads_by_embedding(
            conn,
            embedder.model_name(),
            &query_vector,
            top_k,
        )?;
        attachment_hits = collect_attachment_chunk_hits(conn, key, question, top_k)?;

        let mut contexts_with_distance: Vec<(f64, String)> = Vec::new();
        for sm in similar_messages {
            let context =
                db::build_message_rag_context(conn, key, &sm.message.id, &sm.message.content)
                    .unwrap_or_else(|_| sm.message.content.clone());
            contexts_with_distance.push((sm.distance, context));
        }
        let mut seen_todos = std::collections::HashSet::new();
        for st in similar_todos {
            if !seen_todos.insert(st.todo_id.clone()) {
                continue;
            }
            let ctx = match build_todo_thread_context(conn, key, &st.todo_id) {
                Ok(v) => v,
                Err(_) => continue,
            };
            contexts_with_distance.push((st.distance, ctx));
        }
        for hit in &attachment_hits {
            contexts_with_distance.push((hit.distance, attachment_chunk_context_text(hit)));
        }

        contexts_with_distance
            .sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        contexts_with_distance.truncate(top_k);
        contexts = contexts_with_distance
            .into_iter()
            .map(|(_, ctx)| ctx)
            .collect();
    }

    let resources_catalog = build_attachment_resources_catalog(conn, key, &attachment_hits)?;
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts,
        actions.as_deref(),
        history.as_deref(),
        resources_catalog.as_deref(),
    );

    let mut has_text = false;
    let mut assistant_text = String::new();
    let result = provider.stream_answer(&prompt, &mut |ev| {
        let done = ev.done;
        let text_delta = ev.text_delta.clone();
        on_event(ev)?;

        if !done && !text_delta.is_empty() {
            has_text = true;
            assistant_text.push_str(&text_delta);
        }

        Ok(())
    });

    match result {
        Ok(()) => {
            if !has_text {
                return Err(anyhow!("empty response from LLM"));
            }

            let user_message =
                db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
            let assistant_message = db::insert_message_non_memory(
                conn,
                key,
                conversation_id,
                "assistant",
                &assistant_text,
            )?;

            Ok(AskAiResult {
                user_message_id: user_message.id,
                assistant_message_id: assistant_message.id,
            })
        }
        Err(e) => Err(e),
    }
}

#[allow(clippy::too_many_arguments)]
pub fn ask_ai_with_provider_using_active_embeddings(
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
    let mut contexts: Vec<String> = Vec::new();
    let mut attachment_hits: Vec<db::SimilarAttachmentChunk> = Vec::new();
    if top_k > 0 {
        db::process_pending_message_embeddings_active(conn, key, app_dir, 1024)?;
        db::process_pending_todo_embeddings_active(conn, key, app_dir, 1024)?;
        db::process_pending_todo_activity_embeddings_active(conn, key, app_dir, 1024)?;

        let top_k = top_k.max(1);

        let top_k_candidate_messages = (top_k.saturating_mul(8)).min(200).max(top_k);
        let top_k_candidate_todos = (top_k.saturating_mul(4)).min(80).max(top_k);
        let top_k_candidate_attachments = (top_k.saturating_mul(6)).min(120).max(top_k);

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
        attachment_hits =
            collect_attachment_chunk_hits(conn, key, question, top_k_candidate_attachments)?;

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
            });
        }

        for hit in &attachment_hits {
            candidates.push(ContextItem {
                source: ContextSource::AttachmentChunk,
                id: format!(
                    "{}:{}:{}",
                    hit.attachment_sha256, hit.kind, hit.chunk_index
                ),
                created_at_ms: attachment_created_at_ms(conn, &hit.attachment_sha256),
                distance: Some(hit.distance),
                text: attachment_chunk_context_text(hit),
            });
        }

        contexts = build_contexts_v2(question, candidates, top_k);
    }

    let resources_catalog = build_attachment_resources_catalog(conn, key, &attachment_hits)?;
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts,
        actions.as_deref(),
        history.as_deref(),
        resources_catalog.as_deref(),
    );

    let mut has_text = false;
    let mut assistant_text = String::new();
    let result = provider.stream_answer(&prompt, &mut |ev| {
        let done = ev.done;
        let text_delta = ev.text_delta.clone();
        on_event(ev)?;

        if !done && !text_delta.is_empty() {
            has_text = true;
            assistant_text.push_str(&text_delta);
        }

        Ok(())
    });

    match result {
        Ok(()) => {
            if !has_text {
                return Err(anyhow!("empty response from LLM"));
            }

            let user_message =
                db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
            let assistant_message = db::insert_message_non_memory(
                conn,
                key,
                conversation_id,
                "assistant",
                &assistant_text,
            )?;

            Ok(AskAiResult {
                user_message_id: user_message.id,
                assistant_message_id: assistant_message.id,
            })
        }
        Err(e) => Err(e),
    }
}

#[allow(clippy::too_many_arguments)]
pub fn ask_ai_with_provider_using_active_embeddings_time_window(
    conn: &Connection,
    key: &[u8; 32],
    _app_dir: &Path,
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    time_start_ms: i64,
    time_end_ms: i64,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    let mut contexts: Vec<String> = Vec::new();
    let mut attachment_hits: Vec<db::SimilarAttachmentChunk> = Vec::new();
    if top_k > 0 {
        let conversation_filter = match focus {
            Focus::AllMemories => None,
            Focus::ThisThread => Some(conversation_id),
        };

        let mut candidates: Vec<ContextItem> = Vec::new();

        for m in db::list_memory_messages_in_range(
            conn,
            key,
            conversation_filter,
            time_start_ms,
            time_end_ms,
            800,
        )? {
            let context =
                db::build_message_rag_context(conn, key, &m.id, &m.content).unwrap_or(m.content);
            candidates.push(ContextItem {
                source: ContextSource::Message,
                id: m.id,
                created_at_ms: m.created_at_ms,
                distance: None,
                text: context,
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
            });
        }

        let mut seen_todos: std::collections::HashSet<String> = std::collections::HashSet::new();
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
            });
        }

        attachment_hits = collect_attachment_chunk_hits(conn, key, question, top_k.max(1))?;
        for hit in &attachment_hits {
            candidates.push(ContextItem {
                source: ContextSource::AttachmentChunk,
                id: format!(
                    "{}:{}:{}",
                    hit.attachment_sha256, hit.kind, hit.chunk_index
                ),
                created_at_ms: attachment_created_at_ms(conn, &hit.attachment_sha256),
                distance: Some(hit.distance),
                text: attachment_chunk_context_text(hit),
            });
        }

        contexts = build_contexts_v2(question, candidates, top_k.max(1));
    }

    let resources_catalog = build_attachment_resources_catalog(conn, key, &attachment_hits)?;
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history_in_range(
        conn,
        key,
        conversation_id,
        time_start_ms,
        time_end_ms,
    )?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts,
        actions.as_deref(),
        history.as_deref(),
        resources_catalog.as_deref(),
    );

    let mut has_text = false;
    let mut assistant_text = String::new();
    let result = provider.stream_answer(&prompt, &mut |ev| {
        let done = ev.done;
        let text_delta = ev.text_delta.clone();
        on_event(ev)?;

        if !done && !text_delta.is_empty() {
            has_text = true;
            assistant_text.push_str(&text_delta);
        }

        Ok(())
    });

    match result {
        Ok(()) => {
            if !has_text {
                return Err(anyhow!("empty response from LLM"));
            }

            let user_message =
                db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
            let assistant_message = db::insert_message_non_memory(
                conn,
                key,
                conversation_id,
                "assistant",
                &assistant_text,
            )?;

            Ok(AskAiResult {
                user_message_id: user_message.id,
                assistant_message_id: assistant_message.id,
            })
        }
        Err(e) => Err(e),
    }
}

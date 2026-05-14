#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_semantic_parse_message_action_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    text: String,
    now_local_iso: String,
    locale: String,
    day_end_minutes: i32,
    candidates: Vec<semantic_parse::TodoCandidate>,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<String> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }

    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let available_tags = db::list_available_tags_for_semantic_parse(&conn, &key, 200)?;

    let provider = llm::gateway::CloudGatewayProvider::new_with_purpose(
        gateway_base_url,
        firebase_id_token,
        model_name,
        None,
        "semantic_parse".to_string(),
    );

    semantic_parse::semantic_parse_message_action_json(
        &provider,
        &text,
        now_local_iso.trim(),
        locale.trim(),
        day_end_minutes,
        &candidates,
        &available_tags,
    )
}

#[flutter_rust_bridge::frb]
pub fn ai_semantic_parse_ask_ai_time_window(
    app_dir: String,
    key: Vec<u8>,
    question: String,
    now_local_iso: String,
    locale: String,
    first_day_of_week_index: i32,
    local_day: String,
) -> Result<String> {
    let result = (|| -> Result<String> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let provider = llm::answer_provider_from_profile(&profile)?;
        let result = semantic_parse::semantic_parse_ask_ai_time_window_json(
            provider.as_ref(),
            &question,
            now_local_iso.trim(),
            locale.trim(),
            first_day_of_week_index,
        );

        match result {
            Ok(json) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "semantic_parse",
                        None,
                        None,
                        None,
                    );
                }
                Ok(json)
            }
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "semantic_parse",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    result
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_semantic_parse_ask_ai_time_window_cloud_gateway(
    _app_dir: String,
    key: Vec<u8>,
    question: String,
    now_local_iso: String,
    locale: String,
    first_day_of_week_index: i32,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<String> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }

    let _key = key_from_bytes(key)?;

    // Cloud gateway task-priority usage is tagged server-side via the provider
    // purpose. We intentionally do not write a local `llm_usage_daily` row here
    // because this route does not depend on a local active LLM profile id or local
    // token accounting.
    let provider = llm::gateway::CloudGatewayProvider::new_with_purpose(
        gateway_base_url,
        firebase_id_token,
        model_name,
        None,
        "semantic_parse".to_string(),
    );

    semantic_parse::semantic_parse_ask_ai_time_window_json(
        &provider,
        &question,
        now_local_iso.trim(),
        locale.trim(),
        first_day_of_week_index,
    )
}

#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    local_day: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::answer_provider_from_profile(&profile)?;
        let result = rag::ask_ai_with_provider_using_active_embeddings(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            provider.as_ref(),
            &mut |ev| {
                crate::api::ask_ai_stream_controls::emit_control_if_any(
                    &sink,
                    ev.role.as_deref(),
                )?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Ok(())
            }
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn rag_ask_ai_stream_time_window(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: i64,
    time_end_ms: i64,
    local_day: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::answer_provider_from_profile(&profile)?;
        let result = rag::ask_ai_with_provider_using_active_embeddings_time_window(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            time_start_ms,
            time_end_ms,
            provider.as_ref(),
            &mut |ev| {
                crate::api::ask_ai_stream_controls::emit_control_if_any(
                    &sink,
                    ev.role.as_deref(),
                )?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Ok(())
            }
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_with_brok_embeddings(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    local_day: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let (_emb_profile_id, emb_profile) = db::load_active_embedding_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active embedding profile configured"))?;

        if emb_profile.provider_type != "openai-compatible" {
            return Err(anyhow!(
                "unsupported embedding provider_type: {}",
                emb_profile.provider_type
            ));
        }

        let embeddings_base_url = emb_profile
            .base_url
            .filter(|v| !v.trim().is_empty())
            .ok_or_else(|| anyhow!("missing embedding base_url"))?;
        let embeddings_api_key = emb_profile
            .api_key
            .filter(|v| !v.trim().is_empty())
            .ok_or_else(|| anyhow!("missing embedding api_key"))?;
        let embeddings_model_name = emb_profile.model_name;

        let embedder = embedding::BrokEmbedder::new(
            embeddings_base_url,
            embeddings_api_key,
            embeddings_model_name,
        );

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::answer_provider_from_profile(&profile)?;

        let result = rag::ask_ai_with_provider_using_embedder(
            &conn,
            &key,
            &embedder,
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            provider.as_ref(),
            &mut |ev| {
                crate::api::ask_ai_stream_controls::emit_control_if_any(
                    &sink,
                    ev.role.as_deref(),
                )?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Ok(())
            }
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn rag_ask_ai_stream_with_brok_embeddings_time_window(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: i64,
    time_end_ms: i64,
    local_day: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::answer_provider_from_profile(&profile)?;

        let result = rag::ask_ai_with_provider_using_active_embeddings_time_window(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            time_start_ms,
            time_end_ms,
            provider.as_ref(),
            &mut |ev| {
                crate::api::ask_ai_stream_controls::emit_control_if_any(
                    &sink,
                    ev.role.as_deref(),
                )?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Ok(())
            }
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        if gateway_base_url.trim().is_empty() {
            return Err(anyhow!("missing gateway_base_url"));
        }
        if firebase_id_token.trim().is_empty() {
            return Err(anyhow!("missing firebase_id_token"));
        }

        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::gateway::CloudGatewayProvider::new(
            gateway_base_url,
            firebase_id_token,
            model_name,
            None,
        );

        let result = rag::ask_ai_with_provider_using_active_embeddings(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            &provider,
            &mut |ev| {
                crate::api::ask_ai_stream_controls::emit_control_if_any(
                    &sink,
                    ev.role.as_deref(),
                )?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => Ok(()),
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => Err(e),
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_cloud_gateway_time_window(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: i64,
    time_end_ms: i64,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        if gateway_base_url.trim().is_empty() {
            return Err(anyhow!("missing gateway_base_url"));
        }
        if firebase_id_token.trim().is_empty() {
            return Err(anyhow!("missing firebase_id_token"));
        }

        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::gateway::CloudGatewayProvider::new(
            gateway_base_url,
            firebase_id_token,
            model_name,
            None,
        );

        let result = rag::ask_ai_with_provider_using_active_embeddings_time_window(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            time_start_ms,
            time_end_ms,
            &provider,
            &mut |ev| {
                crate::api::ask_ai_stream_controls::emit_control_if_any(
                    &sink,
                    ev.role.as_deref(),
                )?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => Ok(()),
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => Err(e),
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_cloud_gateway_with_embeddings(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    embeddings_model_name: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        if gateway_base_url.trim().is_empty() {
            return Err(anyhow!("missing gateway_base_url"));
        }
        if firebase_id_token.trim().is_empty() {
            return Err(anyhow!("missing firebase_id_token"));
        }
        if embeddings_model_name.trim().is_empty() {
            return Err(anyhow!("missing embeddings_model_name"));
        }

        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let embedder = embedding::CloudGatewayEmbedder::new(
            gateway_base_url.clone(),
            firebase_id_token.clone(),
            embeddings_model_name,
        );
        let provider = llm::gateway::CloudGatewayProvider::new(
            gateway_base_url,
            firebase_id_token,
            model_name,
            None,
        );

        let result = rag::ask_ai_with_provider_using_embedder(
            &conn,
            &key,
            &embedder,
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            &provider,
            &mut |ev| {
                crate::api::ask_ai_stream_controls::emit_control_if_any(
                    &sink,
                    ev.role.as_deref(),
                )?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => Ok(()),
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => Err(e),
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_cloud_gateway_with_embeddings_time_window(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: i64,
    time_end_ms: i64,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    embeddings_model_name: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        if gateway_base_url.trim().is_empty() {
            return Err(anyhow!("missing gateway_base_url"));
        }
        if firebase_id_token.trim().is_empty() {
            return Err(anyhow!("missing firebase_id_token"));
        }
        if embeddings_model_name.trim().is_empty() {
            return Err(anyhow!("missing embeddings_model_name"));
        }

        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        // Time-window RAG doesn't need remote embeddings; keep the signature for Flutter routing parity.
        let provider = llm::gateway::CloudGatewayProvider::new(
            gateway_base_url,
            firebase_id_token,
            model_name,
            None,
        );

        let result = rag::ask_ai_with_provider_using_active_embeddings_time_window(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            time_start_ms,
            time_end_ms,
            &provider,
            &mut |ev| {
                crate::api::ask_ai_stream_controls::emit_control_if_any(
                    &sink,
                    ev.role.as_deref(),
                )?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => Ok(()),
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => Err(e),
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

/// Deprecated compatibility path:
/// keep deterministic fixed-salt derivation only for legacy migration flows.
/// New recovery flows should use `sync::recovery_key` envelope APIs.
#[flutter_rust_bridge::frb]
pub fn sync_derive_key(passphrase: String) -> Result<Vec<u8>> {
    let kdf = KdfParams {
        m_cost_kib: 8 * 1024,
        t_cost: 2,
        p_cost: 1,
    };
    let key = derive_root_key(&passphrase, b"secondloop-sync1", &kdf)?;
    Ok(key.to_vec())
}

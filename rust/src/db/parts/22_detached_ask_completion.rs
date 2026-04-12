pub fn claim_detached_ask_completion_request_id(
    conn: &Connection,
    request_id: &str,
    conversation_id: &str,
) -> Result<bool> {
    let request_id = request_id.trim();
    let conversation_id = conversation_id.trim();
    if request_id.is_empty() || conversation_id.is_empty() {
        return Ok(false);
    }

    let now = now_ms();
    let claimed = conn.execute(
        r#"
INSERT INTO detached_ask_completion_claims (
  request_id, conversation_id, user_message_id, assistant_message_id, created_at_ms, updated_at_ms
)
VALUES (?1, ?2, NULL, NULL, ?3, ?3)
ON CONFLICT(request_id, conversation_id) DO NOTHING
"#,
        params![request_id, conversation_id, now],
    )?;

    Ok(claimed != 0)
}

pub fn get_detached_ask_completion_message_ids(
    conn: &Connection,
    request_id: &str,
    conversation_id: &str,
) -> Result<Option<(String, String)>> {
    let request_id = request_id.trim();
    let conversation_id = conversation_id.trim();
    if request_id.is_empty() || conversation_id.is_empty() {
        return Ok(None);
    }

    conn.query_row(
        r#"SELECT user_message_id, assistant_message_id
           FROM detached_ask_completion_claims
           WHERE request_id = ?1
             AND conversation_id = ?2"#,
        params![request_id, conversation_id],
        |row| {
            Ok((
                row.get::<_, Option<String>>(0)?,
                row.get::<_, Option<String>>(1)?,
            ))
        },
    )
    .optional()
    .map(|row| {
        row.and_then(|(user_message_id, assistant_message_id)| {
            Some((user_message_id?, assistant_message_id?))
        })
    })
    .map_err(Into::into)
}

pub fn record_detached_ask_completion_message_ids(
    conn: &Connection,
    request_id: &str,
    conversation_id: &str,
    user_message_id: &str,
    assistant_message_id: &str,
) -> Result<()> {
    let request_id = request_id.trim();
    let conversation_id = conversation_id.trim();
    let user_message_id = user_message_id.trim();
    let assistant_message_id = assistant_message_id.trim();
    if request_id.is_empty()
        || conversation_id.is_empty()
        || user_message_id.is_empty()
        || assistant_message_id.is_empty()
    {
        return Ok(());
    }

    conn.execute(
        r#"UPDATE detached_ask_completion_claims
           SET user_message_id = ?2,
               assistant_message_id = ?3,
               updated_at_ms = ?4
           WHERE request_id = ?1
             AND conversation_id = ?5"#,
        params![
            request_id,
            user_message_id,
            assistant_message_id,
            now_ms(),
            conversation_id
        ],
    )?;
    Ok(())
}

pub fn apply_detached_ask_completion_once(
    conn: &Connection,
    key: &[u8; 32],
    request_id: &str,
    conversation_id: &str,
    question: &str,
    answer: &str,
    citations_json: Option<&str>,
) -> Result<bool> {
    let request_id = request_id.trim();
    let conversation_id = conversation_id.trim();
    let question = question.trim();
    let answer = answer.trim();
    if request_id.is_empty() || conversation_id.is_empty() || question.is_empty() || answer.is_empty()
    {
        return Ok(false);
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<bool> = (|| {
        if !claim_detached_ask_completion_request_id(conn, request_id, conversation_id)? {
            if get_detached_ask_completion_message_ids(conn, request_id, conversation_id)?.is_some()
            {
                return Ok(false);
            }
        }

        let user_message = insert_message_non_memory(conn, key, conversation_id, "user", question)?;
        let assistant_message = insert_message_non_memory_with_citations(
            conn,
            key,
            conversation_id,
            "assistant",
            answer,
            citations_json,
        )?;
        record_detached_ask_completion_message_ids(
            conn,
            request_id,
            conversation_id,
            &user_message.id,
            &assistant_message.id,
        )?;
        Ok(true)
    })();

    match result {
        Ok(applied) => {
            conn.execute_batch("COMMIT;")?;
            Ok(applied)
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

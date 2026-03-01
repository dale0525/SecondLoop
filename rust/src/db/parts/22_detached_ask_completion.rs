pub fn apply_detached_ask_completion_once(
    conn: &Connection,
    key: &[u8; 32],
    request_id: &str,
    conversation_id: &str,
    question: &str,
    answer: &str,
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
        let now = now_ms();
        let claimed = conn.execute(
            r#"
INSERT INTO detached_ask_completion_claims (
  request_id, conversation_id, created_at_ms, updated_at_ms
)
VALUES (?1, ?2, ?3, ?3)
ON CONFLICT(request_id) DO NOTHING
"#,
            params![request_id, conversation_id, now],
        )?;

        if claimed == 0 {
            return Ok(false);
        }

        insert_message(conn, key, conversation_id, "user", question)?;
        insert_message(conn, key, conversation_id, "assistant", answer)?;
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

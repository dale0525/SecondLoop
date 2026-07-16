use super::*;

impl StructuredContentService {
    pub async fn owns_oauth_authorization(
        &self,
        session_id: &str,
        content_id: &str,
        authorization_id: &str,
    ) -> anyhow::Result<bool> {
        validate_session_id(session_id)?;
        validate_id(content_id, "content id")?;
        validate_id(authorization_id, "OAuth authorization id")?;
        let owned: i64 = sqlx::query_scalar(
            r#"SELECT EXISTS(
                 SELECT 1
                 FROM structured_action_receipts r
                 INNER JOIN structured_action_bindings b ON b.binding_id = r.binding_id
                 INNER JOIN sessions s ON s.id = b.session_id
                 WHERE b.session_id = ? AND b.content_id = ? AND b.intent = 'oauth.start'
                   AND json_extract(r.result_json, '$.payload.authorizationId') = ?
                   AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ?
                   AND s.user_id = ? AND s.device_id = ?
               )"#,
        )
        .bind(session_id)
        .bind(content_id)
        .bind(authorization_id)
        .bind(&self.scope.app_id)
        .bind(&self.scope.agent_id)
        .bind(&self.scope.tenant_id)
        .bind(&self.scope.user_id)
        .bind(&self.scope.device_id)
        .fetch_one(self.storage.pool())
        .await?;
        Ok(owned != 0)
    }

    pub async fn update_oauth_authorization_result(
        &self,
        authorization_id: &str,
        result: Value,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        validate_id(authorization_id, "OAuth authorization id")?;
        validate_public_payload(&result)?;
        let mut tx = self.storage.pool().begin_with("BEGIN IMMEDIATE").await?;
        let row = sqlx::query(
            r#"SELECT r.result_json, b.binding_id, b.session_id, b.content_id, b.action_id
               FROM structured_action_receipts r
               INNER JOIN structured_action_bindings b ON b.binding_id = r.binding_id
               INNER JOIN sessions s ON s.id = b.session_id
               WHERE b.intent = 'oauth.start'
                 AND json_extract(r.result_json, '$.payload.authorizationId') = ?
                 AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ?
                 AND s.user_id = ? AND s.device_id = ?"#,
        )
        .bind(authorization_id)
        .bind(&self.scope.app_id)
        .bind(&self.scope.agent_id)
        .bind(&self.scope.tenant_id)
        .bind(&self.scope.user_id)
        .bind(&self.scope.device_id)
        .fetch_optional(&mut *tx)
        .await?;
        let Some(row) = row else {
            tx.rollback().await?;
            return Ok(false);
        };
        let mut receipt: StructuredActionReceipt =
            serde_json::from_str(&row.try_get::<String, _>("result_json")?)?;
        receipt.payload = result;
        receipt.replayed = false;
        let binding_id: String = row.try_get("binding_id")?;
        let session_id: String = row.try_get("session_id")?;
        let content_id: String = row.try_get("content_id")?;
        let action_id: String = row.try_get("action_id")?;
        sqlx::query(
            "UPDATE structured_action_receipts SET result_json = ?, completed_at = ? WHERE binding_id = ?",
        )
        .bind(serde_json::to_string(&receipt)?)
        .bind(now.to_rfc3339())
        .bind(&binding_id)
        .execute(&mut *tx)
        .await?;
        append_session_event(
            &mut tx,
            &session_id,
            None,
            &RuntimeEvent::StructuredContentActionAccepted {
                receipt: receipt.clone(),
            },
            now,
        )
        .await?;
        advance_content_for_result(
            &mut tx,
            &session_id,
            &content_id,
            &action_id,
            StructuredActionIntent::OauthStart,
            &receipt.payload,
            now + Duration::microseconds(1),
        )
        .await?;
        tx.commit().await?;
        Ok(true)
    }
}

pub(super) async fn advance_content_for_result(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
    content_id: &str,
    action_id: &str,
    intent: StructuredActionIntent,
    result: &Value,
    now: DateTime<Utc>,
) -> anyhow::Result<()> {
    let value: Option<String> = sqlx::query_scalar(
        "SELECT content_json FROM structured_content_state WHERE session_id = ? AND content_id = ? AND deleted = 0",
    )
    .bind(session_id)
    .bind(content_id)
    .fetch_optional(&mut **tx)
    .await?
    .flatten();
    let Some(value) = value else {
        return Ok(());
    };
    let mut content: StructuredContent = serde_json::from_str(&value)?;
    let payload = content
        .payload
        .as_object_mut()
        .ok_or_else(|| anyhow::anyhow!("structured content payload must be an object"))?;
    if let Some(actions) = payload.get_mut("actions").and_then(Value::as_array_mut) {
        actions.retain(|action| action.get("id").and_then(Value::as_str) != Some(action_id));
    }
    if let Some(bindings) = payload
        .get_mut("actionBindings")
        .and_then(Value::as_object_mut)
    {
        bindings.remove(action_id);
    }
    payload.insert("status".into(), action_status(result));
    let fields = action_result_fields(intent, result);
    if !fields.is_empty() {
        payload.insert("fields".into(), Value::Array(fields));
    }
    content.revision = content
        .revision
        .checked_add(1)
        .ok_or_else(|| anyhow::anyhow!("structured content revision overflow"))?;
    content.validate()?;
    let updated = sqlx::query(
        "UPDATE structured_content_state SET revision = ?, content_json = ?, updated_at = ? WHERE session_id = ? AND content_id = ? AND deleted = 0",
    )
    .bind(i64::try_from(content.revision)?)
    .bind(serde_json::to_string(&content)?)
    .bind(now.to_rfc3339())
    .bind(session_id)
    .bind(content_id)
    .execute(&mut **tx)
    .await?;
    anyhow::ensure!(
        updated.rows_affected() == 1,
        "structured content update conflict"
    );
    sqlx::query(
        "UPDATE structured_action_bindings SET content_revision = ?, updated_at = ? WHERE session_id = ? AND content_id = ? AND state = 'pending'",
    )
    .bind(i64::try_from(content.revision)?)
    .bind(now.to_rfc3339())
    .bind(session_id)
    .bind(content_id)
    .execute(&mut **tx)
    .await?;
    append_session_event(
        tx,
        session_id,
        None,
        &RuntimeEvent::StructuredContentPublished { content },
        now,
    )
    .await
}

fn action_result_fields(intent: StructuredActionIntent, result: &Value) -> Vec<Value> {
    match intent {
        StructuredActionIntent::OauthStart
        | StructuredActionIntent::OauthStatus
        | StructuredActionIntent::OauthCancel => oauth_result_fields(result),
        StructuredActionIntent::ScheduleCreate | StructuredActionIntent::ScheduleStatus => {
            schedule_result_fields(result)
        }
    }
}

fn oauth_result_fields(result: &Value) -> Vec<Value> {
    let mut fields = Vec::new();
    push_field(&mut fields, "Provider", result.get("providerId"));
    if let Some(capabilities) = result
        .get("requestedCapabilities")
        .and_then(Value::as_array)
    {
        let value = capabilities
            .iter()
            .filter_map(Value::as_str)
            .collect::<Vec<_>>()
            .join(", ");
        if !value.is_empty() {
            fields.push(field("Capabilities", value));
        }
    }
    if let Some(bindings) = result.get("bindings").and_then(Value::as_array) {
        let accounts = bindings
            .iter()
            .filter_map(|binding| binding.get("accountId").and_then(Value::as_str))
            .collect::<Vec<_>>()
            .join(", ");
        if !accounts.is_empty() {
            fields.push(field("Account", accounts));
        }
    }
    push_field(&mut fields, "Expires", result.get("expiresAt"));
    fields
}

fn schedule_result_fields(result: &Value) -> Vec<Value> {
    let mut fields = Vec::new();
    push_field(&mut fields, "Schedule ID", result.get("id"));
    push_field(&mut fields, "Next run", result.get("nextRunAt"));
    let schedule = result.get("schedule");
    push_field(
        &mut fields,
        "Timezone",
        schedule.and_then(|value| value.get("timezone")),
    );
    push_field(
        &mut fields,
        "Schedule",
        schedule.and_then(|value| value.get("kind")),
    );
    push_field(
        &mut fields,
        "Misfire policy",
        result.get("misfire").and_then(|value| value.get("kind")),
    );
    fields
}

fn push_field(fields: &mut Vec<Value>, label: &str, value: Option<&Value>) {
    if let Some(value) = value.and_then(display_value) {
        fields.push(field(label, value));
    }
}

fn display_value(value: &Value) -> Option<String> {
    match value {
        Value::String(value) if !value.is_empty() => Some(value.clone()),
        Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

fn field(label: &str, value: impl Into<String>) -> Value {
    serde_json::json!({"label":label,"value":value.into()})
}

fn action_status(result: &Value) -> Value {
    let status = result
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("completed");
    let tone = match status {
        "completed" | "active" | "connected" | "delivered" => "success",
        "cancelled" | "denied" | "expired" | "failed" => "danger",
        "paused" => "warning",
        _ => "info",
    };
    let label = status
        .split('_')
        .filter(|segment| !segment.is_empty())
        .map(|segment| {
            let mut characters = segment.chars();
            characters.next().map_or_else(String::new, |first| {
                first.to_uppercase().collect::<String>() + characters.as_str()
            })
        })
        .collect::<Vec<_>>()
        .join(" ");
    serde_json::json!({"label": label, "tone": tone})
}

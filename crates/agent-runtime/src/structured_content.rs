use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::sync::{Arc, RwLock};

const MAX_PAYLOAD_BYTES: usize = 256 * 1024;
const MAX_FALLBACK_BYTES: usize = 32 * 1024;
const MAX_JSON_DEPTH: usize = 16;
const MAX_JSON_NODES: usize = 4_096;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StructuredContentAudience {
    User,
    Owner,
    Developer,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct StructuredContent {
    pub content_id: String,
    pub mime_type: String,
    pub schema_version: String,
    pub payload: Value,
    pub fallback_text: String,
    pub audience: StructuredContentAudience,
    pub owner: String,
    pub revision: u64,
}

impl StructuredContent {
    pub fn validate(&self) -> anyhow::Result<()> {
        validate_id(&self.content_id, "content id")?;
        validate_id(&self.owner, "content owner")?;
        anyhow::ensure!(self.revision > 0, "content revision must be positive");
        anyhow::ensure!(
            valid_mime_type(&self.mime_type),
            "structured content MIME type is invalid"
        );
        anyhow::ensure!(
            !self.schema_version.trim().is_empty() && self.schema_version.len() <= 64,
            "structured content schema version is invalid"
        );
        anyhow::ensure!(
            serde_json::to_vec(&self.payload)?.len() <= MAX_PAYLOAD_BYTES,
            "structured content payload exceeds limit"
        );
        anyhow::ensure!(
            !self.fallback_text.trim().is_empty() && self.fallback_text.len() <= MAX_FALLBACK_BYTES,
            "structured content fallback text is invalid"
        );
        validate_public_payload(&self.payload)?;
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub enum StructuredActionIntent {
    #[serde(rename = "oauth.start")]
    OauthStart,
    #[serde(rename = "oauth.status")]
    OauthStatus,
    #[serde(rename = "oauth.cancel")]
    OauthCancel,
    #[serde(rename = "schedule.create")]
    ScheduleCreate,
    #[serde(rename = "schedule.status")]
    ScheduleStatus,
}

impl StructuredActionIntent {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::OauthStart => "oauth.start",
            Self::OauthStatus => "oauth.status",
            Self::OauthCancel => "oauth.cancel",
            Self::ScheduleCreate => "schedule.create",
            Self::ScheduleStatus => "schedule.status",
        }
    }
}

impl std::str::FromStr for StructuredActionIntent {
    type Err = anyhow::Error;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "oauth.start" => Ok(Self::OauthStart),
            "oauth.status" => Ok(Self::OauthStatus),
            "oauth.cancel" => Ok(Self::OauthCancel),
            "schedule.create" => Ok(Self::ScheduleCreate),
            "schedule.status" => Ok(Self::ScheduleStatus),
            _ => anyhow::bail!("structured action intent is invalid"),
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StructuredActionConstraints {
    #[serde(default)]
    pub provider_ids: Vec<String>,
    #[serde(default)]
    pub connector_ids: Vec<String>,
    #[serde(default)]
    pub capabilities: Vec<String>,
}

impl StructuredActionConstraints {
    pub fn validate(&self) -> anyhow::Result<()> {
        for values in [&self.provider_ids, &self.connector_ids, &self.capabilities] {
            anyhow::ensure!(
                values.len() <= 32,
                "structured action constraints are too large"
            );
            let mut deduplicated = values.clone();
            deduplicated.sort();
            deduplicated.dedup();
            anyhow::ensure!(
                deduplicated.len() == values.len(),
                "structured action constraints contain duplicates"
            );
            for value in values {
                validate_id(value, "action constraint")?;
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StructuredActionBindingRequest {
    pub action_id: String,
    pub intent: StructuredActionIntent,
    pub idempotency_key: String,
    pub expires_at: DateTime<Utc>,
    #[serde(default)]
    pub parameters: Value,
    #[serde(default = "empty_input_schema")]
    pub input_schema: Value,
    #[serde(default)]
    pub constraints: StructuredActionConstraints,
}

impl StructuredActionBindingRequest {
    pub fn validate(&self, now: DateTime<Utc>) -> anyhow::Result<()> {
        validate_id(&self.action_id, "action id")?;
        validate_id(&self.idempotency_key, "action idempotency key")?;
        anyhow::ensure!(self.expires_at > now, "structured action expired");
        anyhow::ensure!(
            self.expires_at <= now + chrono::Duration::hours(24),
            "structured action expiry exceeds limit"
        );
        validate_private_payload(&self.parameters)?;
        validate_input_schema(&self.input_schema)?;
        self.constraints.validate()
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StructuredActionBindingView {
    pub binding_id: String,
    pub action_id: String,
    pub intent: StructuredActionIntent,
    pub expires_at: DateTime<Utc>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct StructuredActionExecution {
    pub binding_id: String,
    pub claim_token: String,
    pub claim_epoch: u64,
    pub session_id: String,
    pub content_id: String,
    pub content_revision: u64,
    pub action_id: String,
    pub intent: StructuredActionIntent,
    pub parameters: Value,
    pub input: Value,
    pub constraints: StructuredActionConstraints,
    pub idempotency_key: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct StructuredContentAction {
    pub action_id: String,
    pub content_id: String,
    pub content_revision: u64,
    pub owner: String,
    pub idempotency_key: String,
    pub expires_at: DateTime<Utc>,
    pub payload: Value,
}

impl StructuredContentAction {
    pub fn validate(&self) -> anyhow::Result<()> {
        validate_id(&self.action_id, "action id")?;
        validate_id(&self.content_id, "content id")?;
        validate_id(&self.owner, "action owner")?;
        validate_id(&self.idempotency_key, "action idempotency key")?;
        anyhow::ensure!(
            serde_json::to_vec(&self.payload)?.len() <= MAX_PAYLOAD_BYTES,
            "structured action payload exceeds limit"
        );
        validate_private_payload(&self.payload)?;
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct StructuredActionReceipt {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub binding_id: Option<String>,
    pub action_id: String,
    pub content_id: String,
    pub content_revision: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub intent: Option<StructuredActionIntent>,
    pub replayed: bool,
    pub payload: Value,
}

#[derive(Clone, Default)]
pub struct StructuredContentRegistry {
    inner: Arc<RwLock<StructuredContentState>>,
}

#[derive(Default)]
struct StructuredContentState {
    content: BTreeMap<String, StructuredContent>,
    consumed_actions: BTreeMap<String, StructuredActionReceipt>,
    deleted: BTreeMap<String, StructuredContentTombstone>,
}

struct StructuredContentTombstone {
    owner: String,
    revision: u64,
}

impl StructuredContentRegistry {
    pub fn publish(&self, content: StructuredContent) -> anyhow::Result<()> {
        content.validate()?;
        let mut state = self
            .inner
            .write()
            .expect("structured content lock poisoned");
        if let Some(tombstone) = state.deleted.get(&content.content_id) {
            anyhow::bail!(
                "deleted structured content identifier owned by {} cannot be reused after revision {}",
                tombstone.owner,
                tombstone.revision
            );
        }
        if let Some(previous) = state.content.get(&content.content_id) {
            anyhow::ensure!(
                previous.owner == content.owner,
                "structured content owner cannot change"
            );
            anyhow::ensure!(
                content.revision == previous.revision + 1,
                "structured content revision conflict"
            );
        } else {
            anyhow::ensure!(
                content.revision == 1,
                "initial content revision must be one"
            );
        }
        state.content.insert(content.content_id.clone(), content);
        Ok(())
    }

    pub fn get(&self, content_id: &str) -> Option<StructuredContent> {
        self.inner
            .read()
            .expect("structured content lock poisoned")
            .content
            .get(content_id)
            .cloned()
    }

    pub fn replay(&self, audience: StructuredContentAudience) -> Vec<StructuredContent> {
        self.inner
            .read()
            .expect("structured content lock poisoned")
            .content
            .values()
            .filter(|content| content.audience == audience)
            .cloned()
            .collect()
    }

    pub fn delete(&self, content_id: &str, owner: &str, revision: u64) -> anyhow::Result<bool> {
        let mut state = self
            .inner
            .write()
            .expect("structured content lock poisoned");
        let Some(content) = state.content.get(content_id) else {
            return Ok(false);
        };
        anyhow::ensure!(content.owner == owner, "structured content owner mismatch");
        anyhow::ensure!(
            content.revision == revision,
            "structured content revision conflict"
        );
        let tombstone = StructuredContentTombstone {
            owner: content.owner.clone(),
            revision: content.revision + 1,
        };
        state.content.remove(content_id);
        state.deleted.insert(content_id.to_string(), tombstone);
        Ok(true)
    }

    pub fn accept_action(
        &self,
        action: StructuredContentAction,
    ) -> anyhow::Result<StructuredActionReceipt> {
        action.validate()?;
        let mut state = self
            .inner
            .write()
            .expect("structured content lock poisoned");
        if let Some(receipt) = state.consumed_actions.get(&action.idempotency_key) {
            anyhow::ensure!(
                receipt.action_id == action.action_id
                    && receipt.content_id == action.content_id
                    && receipt.content_revision == action.content_revision,
                "structured action idempotency conflict"
            );
            let mut receipt = receipt.clone();
            receipt.replayed = true;
            return Ok(receipt);
        }
        anyhow::ensure!(action.expires_at > Utc::now(), "structured action expired");
        let content = state
            .content
            .get(&action.content_id)
            .ok_or_else(|| anyhow::anyhow!("structured content is unavailable"))?;
        anyhow::ensure!(
            content.owner == action.owner,
            "structured action owner mismatch"
        );
        anyhow::ensure!(
            content.revision == action.content_revision,
            "structured action revision is stale"
        );
        let receipt = StructuredActionReceipt {
            binding_id: None,
            action_id: action.action_id,
            content_id: action.content_id,
            content_revision: action.content_revision,
            intent: None,
            replayed: false,
            payload: action.payload,
        };
        state
            .consumed_actions
            .insert(action.idempotency_key, receipt.clone());
        Ok(receipt)
    }
}

pub(crate) fn validate_id(value: &str, label: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        !value.is_empty()
            && value.len() <= 255
            && value
                .chars()
                .all(|character| character.is_ascii_alphanumeric() || ".-_".contains(character)),
        "invalid {label}"
    );
    Ok(())
}

fn valid_mime_type(value: &str) -> bool {
    let Some((top, subtype)) = value.split_once('/') else {
        return false;
    };
    !top.is_empty()
        && !subtype.is_empty()
        && value.len() <= 128
        && value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || "/.+-".contains(character))
}

pub(crate) fn validate_public_payload(value: &Value) -> anyhow::Result<()> {
    validate_json_shape(value)?;
    reject_active_content(value)?;
    reject_credential_fields(value)?;
    reject_url_fields(value)
}

pub(crate) fn validate_private_payload(value: &Value) -> anyhow::Result<()> {
    anyhow::ensure!(
        serde_json::to_vec(value)?.len() <= MAX_PAYLOAD_BYTES,
        "structured action payload exceeds limit"
    );
    validate_json_shape(value)?;
    reject_active_content(value)?;
    reject_credential_fields(value)
}

pub(crate) fn validate_input(self_schema: &Value, input: &Value) -> anyhow::Result<()> {
    validate_input_schema(self_schema)?;
    let schema = self_schema
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("structured action input schema is invalid"))?;
    let input = input
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("structured action input must be an object"))?;
    let properties = schema
        .get("properties")
        .and_then(Value::as_object)
        .ok_or_else(|| anyhow::anyhow!("structured action input schema is invalid"))?;
    let required = schema
        .get("required")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow::anyhow!("structured action input schema is invalid"))?;
    for name in required {
        let name = name
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("structured action input schema is invalid"))?;
        anyhow::ensure!(
            input.contains_key(name),
            "structured action input is missing a required field"
        );
    }
    anyhow::ensure!(
        input.keys().all(|name| properties.contains_key(name)),
        "structured action input contains unknown fields"
    );
    for (name, value) in input {
        validate_input_value(
            properties
                .get(name)
                .ok_or_else(|| anyhow::anyhow!("structured action input schema is invalid"))?,
            value,
        )?;
    }
    validate_private_payload(&Value::Object(input.clone()))
}

fn validate_input_schema(value: &Value) -> anyhow::Result<()> {
    validate_json_shape(value)?;
    let schema = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("structured action input schema is invalid"))?;
    anyhow::ensure!(
        schema.keys().all(|key| matches!(
            key.as_str(),
            "type" | "properties" | "required" | "additionalProperties"
        )),
        "structured action input schema contains unsupported fields"
    );
    anyhow::ensure!(
        schema.get("type") == Some(&Value::String("object".into())),
        "structured action input schema must describe an object"
    );
    anyhow::ensure!(
        schema.get("additionalProperties") == Some(&Value::Bool(false)),
        "structured action input schema must reject additional properties"
    );
    let properties = schema
        .get("properties")
        .and_then(Value::as_object)
        .ok_or_else(|| anyhow::anyhow!("structured action input schema properties are invalid"))?;
    anyhow::ensure!(
        properties.len() <= 16,
        "structured action input schema has too many properties"
    );
    for (name, property) in properties {
        validate_id(name, "action input field")?;
        validate_input_property(property)?;
    }
    let required = schema
        .get("required")
        .and_then(Value::as_array)
        .ok_or_else(|| {
            anyhow::anyhow!("structured action input schema required fields are invalid")
        })?;
    anyhow::ensure!(
        required.len() <= properties.len(),
        "structured action input schema required fields are invalid"
    );
    for name in required {
        let name = name.as_str().ok_or_else(|| {
            anyhow::anyhow!("structured action input schema required fields are invalid")
        })?;
        anyhow::ensure!(
            properties.contains_key(name),
            "structured action input schema required field is unknown"
        );
    }
    Ok(())
}

fn validate_input_property(value: &Value) -> anyhow::Result<()> {
    let property = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("structured action input property is invalid"))?;
    anyhow::ensure!(
        property
            .keys()
            .all(|key| matches!(key.as_str(), "type" | "minLength" | "maxLength" | "enum")),
        "structured action input property contains unsupported fields"
    );
    let kind = property
        .get("type")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("structured action input property type is invalid"))?;
    anyhow::ensure!(
        matches!(kind, "string" | "boolean" | "number" | "integer"),
        "structured action input property type is unsupported"
    );
    if kind == "string" {
        let maximum = property
            .get("maxLength")
            .and_then(Value::as_u64)
            .unwrap_or(4_096);
        let minimum = property
            .get("minLength")
            .and_then(Value::as_u64)
            .unwrap_or(0);
        anyhow::ensure!(
            maximum <= 4_096 && minimum <= maximum,
            "structured action string limits are invalid"
        );
    } else {
        anyhow::ensure!(
            !property.contains_key("minLength") && !property.contains_key("maxLength"),
            "structured action input property limits are invalid"
        );
    }
    if let Some(values) = property.get("enum") {
        let values = values
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("structured action input enum is invalid"))?;
        anyhow::ensure!(
            !values.is_empty() && values.len() <= 32,
            "structured action input enum is invalid"
        );
    }
    Ok(())
}

fn validate_input_value(schema: &Value, value: &Value) -> anyhow::Result<()> {
    let property = schema.as_object().expect("validated input property");
    let kind = property
        .get("type")
        .and_then(Value::as_str)
        .expect("validated input type");
    let type_matches = match kind {
        "string" => value.is_string(),
        "boolean" => value.is_boolean(),
        "number" => value.is_number(),
        "integer" => value.as_i64().is_some() || value.as_u64().is_some(),
        _ => false,
    };
    anyhow::ensure!(
        type_matches,
        "structured action input field has an invalid type"
    );
    if let Some(text) = value.as_str() {
        let maximum = property
            .get("maxLength")
            .and_then(Value::as_u64)
            .unwrap_or(4_096) as usize;
        let minimum = property
            .get("minLength")
            .and_then(Value::as_u64)
            .unwrap_or(0) as usize;
        anyhow::ensure!(
            (minimum..=maximum).contains(&text.len()),
            "structured action input string has an invalid length"
        );
    }
    if let Some(allowed) = property.get("enum").and_then(Value::as_array) {
        anyhow::ensure!(
            allowed.contains(value),
            "structured action input value is not allowed"
        );
    }
    Ok(())
}

pub(crate) fn empty_input_schema() -> Value {
    serde_json::json!({
        "type": "object",
        "properties": {},
        "required": [],
        "additionalProperties": false
    })
}

fn validate_json_shape(value: &Value) -> anyhow::Result<()> {
    fn walk(value: &Value, depth: usize, nodes: &mut usize) -> anyhow::Result<()> {
        *nodes += 1;
        anyhow::ensure!(
            *nodes <= MAX_JSON_NODES,
            "structured JSON contains too many nodes"
        );
        anyhow::ensure!(
            depth <= MAX_JSON_DEPTH,
            "structured JSON is too deeply nested"
        );
        match value {
            Value::Object(object) => {
                anyhow::ensure!(
                    object.len() <= 256,
                    "structured JSON object contains too many fields"
                );
                for (key, child) in object {
                    anyhow::ensure!(key.len() <= 128, "structured JSON field name is too long");
                    walk(child, depth + 1, nodes)?;
                }
            }
            Value::Array(items) => {
                anyhow::ensure!(
                    items.len() <= 512,
                    "structured JSON array contains too many items"
                );
                for child in items {
                    walk(child, depth + 1, nodes)?;
                }
            }
            Value::String(text) => anyhow::ensure!(
                text.len() <= MAX_PAYLOAD_BYTES,
                "structured JSON string is too large"
            ),
            _ => {}
        }
        Ok(())
    }
    let mut nodes = 0;
    walk(value, 0, &mut nodes)
}

fn reject_active_content(value: &Value) -> anyhow::Result<()> {
    match value {
        Value::Object(object) => {
            for (key, child) in object {
                let normalized = key.to_ascii_lowercase();
                anyhow::ensure!(
                    !matches!(
                        normalized.as_str(),
                        "html" | "script" | "javascript" | "iframe"
                    ),
                    "structured content cannot embed active content"
                );
                reject_active_content(child)?;
            }
        }
        Value::Array(items) => {
            for item in items {
                reject_active_content(item)?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn reject_credential_fields(value: &Value) -> anyhow::Result<()> {
    reject_field_names(
        value,
        |key| {
            matches!(
                key,
                "apikey"
                    | "api_key"
                    | "authorization"
                    | "clientsecret"
                    | "client_secret"
                    | "credential"
                    | "cookie"
                    | "password"
                    | "refreshtoken"
                    | "refresh_token"
                    | "accesstoken"
                    | "access_token"
                    | "token"
                    | "verifier"
            )
        },
        "structured content cannot contain credential-shaped fields",
    )
}

fn reject_url_fields(value: &Value) -> anyhow::Result<()> {
    reject_field_names(
        value,
        |key| matches!(key, "href" | "src" | "url"),
        "structured content cannot contain arbitrary URLs",
    )
}

fn reject_field_names(
    value: &Value,
    forbidden: impl Fn(&str) -> bool + Copy,
    message: &'static str,
) -> anyhow::Result<()> {
    match value {
        Value::Object(object) => {
            for (key, child) in object {
                anyhow::ensure!(!forbidden(&key.to_ascii_lowercase()), message);
                reject_field_names(child, forbidden, message)?;
            }
        }
        Value::Array(items) => {
            for item in items {
                reject_field_names(item, forbidden, message)?;
            }
        }
        _ => {}
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;

    fn content(revision: u64) -> StructuredContent {
        StructuredContent {
            content_id: "briefing-1".into(),
            mime_type: "application/vnd.agentweave.card+json".into(),
            schema_version: "1".into(),
            payload: serde_json::json!({"title": "Daily briefing"}),
            fallback_text: "Daily briefing".into(),
            audience: StructuredContentAudience::User,
            owner: "secretary-agent".into(),
            revision,
        }
    }

    #[test]
    fn publication_requires_monotonic_revision_and_stable_owner() {
        let registry = StructuredContentRegistry::default();
        registry.publish(content(1)).unwrap();
        assert!(registry.publish(content(3)).is_err());
        registry.publish(content(2)).unwrap();
        assert_eq!(registry.get("briefing-1").unwrap().revision, 2);
    }

    #[test]
    fn actions_validate_owner_revision_expiry_and_idempotency() {
        let registry = StructuredContentRegistry::default();
        registry.publish(content(1)).unwrap();
        let action = StructuredContentAction {
            action_id: "open-task".into(),
            content_id: "briefing-1".into(),
            content_revision: 1,
            owner: "secretary-agent".into(),
            idempotency_key: "action-1".into(),
            expires_at: Utc::now() + Duration::minutes(5),
            payload: serde_json::json!({"task_id": "task-1"}),
        };
        assert!(!registry.accept_action(action.clone()).unwrap().replayed);
        assert!(registry.accept_action(action).unwrap().replayed);
    }

    #[test]
    fn active_content_is_rejected_and_text_fallback_is_required() {
        let registry = StructuredContentRegistry::default();
        let mut invalid = content(1);
        invalid.payload = serde_json::json!({"html": "<script>bad()</script>"});
        assert!(registry.publish(invalid).is_err());
        let mut invalid = content(1);
        invalid.fallback_text.clear();
        assert!(registry.publish(invalid).is_err());
    }
}
